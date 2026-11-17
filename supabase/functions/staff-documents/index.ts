import { createClient } from "npm:@supabase/supabase-js@2.109.0";

const env = (name: string) => Deno.env.get(name) ?? "";
const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});
const origin = env("GOYA_PORTAL_ORIGIN") || "https://mehedih99.github.io";
const limit = 5_000_000;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const driveId = /^[A-Za-z0-9_-]{10,}$/;
// Route new types into related folders supported by the existing signed Drive bridge.
const driveCategories = new Map([
  ["emirates-id", "emirates-id"], ["contract", "contract"], ["food-safety", "food-safety"],
  ["health-card", "health-card"], ["work-permit", "contract"], ["residence-visa", "emirates-id"],
  ["health-insurance", "health-card"], ["pic-certificate", "food-safety"],
]);
const isCustom = (category: string) => category.startsWith("custom-") && uuid.test(category.slice(7));
const driveCategory = (category: string) => isCustom(category) ? "contract" : driveCategories.get(category);
const types = new Map([
  ["application/pdf", [37,80,68,70,45]],
  ["image/jpeg", [255,216,255]],
  ["image/png", [137,80,78,71,13,10,26,10]],
]);
const headers = {
  "Access-Control-Allow-Origin": origin,
  "Access-Control-Allow-Headers": "x-goya-session, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  Vary: "Origin",
};
const json = (status: number, body: Record<string, unknown>) => Response.json(body, { status, headers });

function base64(bytes: Uint8Array) {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 32768) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 32768));
  }
  return btoa(binary);
}

async function drive(payload: Record<string, unknown>) {
  const url = env("GOYA_DRIVE_BRIDGE_URL").trim(), secret = env("GOYA_DRIVE_BRIDGE_SECRET").trim();
  if (!/^https:\/\/script\.google\.com\/macros\/s\/[A-Za-z0-9_-]+\/exec$/.test(url) || secret.length < 32) {
    throw Error("Drive connection unavailable");
  }
  const time = Date.now(), message = JSON.stringify(payload), encoder = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), {name:"HMAC",hash:"SHA-256"}, false, ["sign"]);
  const signed = await crypto.subtle.sign("HMAC", key, encoder.encode(time + "." + message));
  const signature = base64(new Uint8Array(signed)).replaceAll("+","-").replaceAll("/","_").replace(/=+$/,"");
  const signal = AbortSignal.timeout(40000);
  let response = await fetch(url, {
    method:"POST", headers:{"Content-Type":"application/json"}, redirect:"manual", signal,
    body:JSON.stringify({time,payload:message,signature}),
  });
  if ([302,303].includes(response.status)) {
    const location = new URL(response.headers.get("location") ?? "",url);
    if (location.origin !== "https://script.googleusercontent.com") throw Error("Invalid Drive redirect");
    response = await fetch(location, {redirect:"error",signal});
  }
  const result = response.ok ? await response.json() : null;
  if (!result?.ok) throw Error("Drive rejected the document");
  return result;
}

async function upload(req: Request, token: string) {
  if (Number(req.headers.get("content-length")) > limit + 16384) {
    return json(413,{error:"Choose a PDF, JPG or PNG up to 5 MB."});
  }
  const form = await req.formData();
  const id = String(form.get("id") ?? ""), category = String(form.get("category") ?? "");
  const staff = String(form.get("staff") ?? "") || null;
  const title = String(form.get("title") ?? "").trim() || null;
  const folderCategory = driveCategory(category);
  if ((staff !== null && !uuid.test(staff)) || (isCustom(category) && (!staff || !title || title.length > 100))) {
    return json(400,{error:"Choose a staff member and enter a valid document title."});
  }
  if (staff === null) {
    const {data: employee} = await db.rpc("goya_hr_staff_identity", {p_token:token});
    if (!employee) return json(401,{error:"Sign in again."});
  }
  const file = form.get("file");
  const type = file instanceof File ? types.get(file.type) : undefined;
  if (!uuid.test(id) || !folderCategory || !(file instanceof File) || !type || !file.size || file.size > limit) {
    return json(400,{error:"Choose a PDF, JPG or PNG up to 5 MB."});
  }
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (!type.every((byte,i) => bytes[i] === byte)) return json(400,{error:"The file content does not match its file type."});
  const sha = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",bytes)),
    byte => byte.toString(16).padStart(2,"0")).join("");
  const name = Array.from(file.name.replace(/[\u0000-\u001f\u007f/\\]/g,"_").trim()).slice(0,180).join("") || "Document";
  const {data: slot,error} = await db.rpc("goya_hr_document_reserve_v2", {
    p_token:token,p_id:id,p_category:category,p_name:name,p_type:file.type,p_size:file.size,p_sha:sha,p_staff:staff,p_title:title,
  });
  if (error || !slot) return json(409,{error:"Unable to prepare this upload. Sign in again or choose the file again."});
  if (slot.complete) return json(200,{ok:true});
  const result = await drive({
    operation:"staff-document-upload",id,category:folderCategory,folder:slot.folder,type:file.type,size:file.size,sha,bytes:base64(bytes),
  });
  if (typeof result.id !== "string" || !driveId.test(result.id)) throw Error("Invalid Drive file reference");
  const {error: failure} = await db.rpc("goya_hr_document_complete_v2",{p_token:token,p_id:id,p_drive:result.id,p_staff:staff});
  if (failure) throw Error("Unable to record the Drive upload");
  return json(200,{ok:true});
}

async function read(req: Request, token: string) {
  const {id,staff = null} = await req.json();
  if (typeof id !== "string" || !uuid.test(id) || (staff !== null && (typeof staff !== "string" || !uuid.test(staff)))) {
    return json(400,{error:"The document is unavailable."});
  }
  const {data: file,error} = await db.rpc("goya_hr_document_private_file",{p_token:token,p_id:id,p_staff:staff});
  if (error || !file) return json(404,{error:"The document is unavailable."});
  const result = await drive({
    operation:"staff-document-read",id,category:driveCategory(file.category),folder:file.folder_key,type:file.mime_type,
    size:file.byte_size,sha:file.sha256,driveId:file.drive_file_id,
  });
  if (typeof result.bytes !== "string" || result.bytes.length !== Math.ceil(file.byte_size/3)*4) {
    throw Error("Invalid Drive response");
  }
  const bytes = Uint8Array.from(atob(result.bytes),char => char.charCodeAt(0));
  if (!types.has(file.mime_type) || bytes.length !== file.byte_size) throw Error("Invalid Drive content");
  return new Response(bytes,{headers:{...headers,"Content-Type":file.mime_type}});
}

Deno.serve(async req => {
  if (req.headers.get("origin") !== origin) return json(403,{error:"Origin denied."});
  if (req.method === "OPTIONS") return new Response(null,{status:204,headers});
  if (req.method !== "POST") return json(405,{error:"Method not allowed."});
  const token = req.headers.get("x-goya-session");
  if (!token || token.length > 256) return json(401,{error:"Sign in again."});
  try {
    const contentType = req.headers.get("content-type") ?? "";
    if (contentType.startsWith("multipart/form-data")) return await upload(req,token);
    if (contentType.startsWith("application/json") && Number(req.headers.get("content-length")) <= 2048) {
      return await read(req,token);
    }
    return json(400,{error:"Invalid document request."});
  } catch {
    return json(502,{error:"Unable to complete the Google Drive request. Please try again."});
  }
});

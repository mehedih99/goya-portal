import { createClient } from "npm:@supabase/supabase-js@2";

const env = (name: string) => Deno.env.get(name) ?? "";
const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});
const origin = env("GOYA_PORTAL_ORIGIN") || "https://mehedih99.github.io";
const maxFile = 5_000_000;
const driveApi = "https://www.googleapis.com/drive/v3";
const folderType = "application/vnd.google-apps.folder";
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const acceptedTypes: Record<string, { ext: string; signature: number[] }> = {
  "application/pdf": { ext: "pdf", signature: [37, 80, 68, 70, 45] },
  "image/jpeg": { ext: "jpg", signature: [255, 216, 255] },
  "image/png": { ext: "png", signature: [137, 80, 78, 71, 13, 10, 26, 10] },
};

async function rpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await db.rpc(name, args);
  if (error) throw new Error("Leave service database request failed");
  return data;
}

async function getDriveId(headers: HeadersInit) {
  const result = await fetch(driveApi + "/files/generateIds?count=1", { headers, signal: AbortSignal.timeout(10000) });
  if (!result.ok) throw new Error("Google Drive could not prepare the upload.");
  const { ids } = await result.json();
  return ids[0];
}

async function getDriveItem(headers: HeadersInit, id: string) {
  const result = await fetch(driveApi + "/files/" + encodeURIComponent(id) +
    "?supportsAllDrives=true&fields=name,parents,trashed,mimeType", { headers, signal: AbortSignal.timeout(10000) });
  return result.ok ? await result.json() : null;
}

async function ensureFolder(headers: HeadersInit, parent: string, name: string) {
  const args = { p_parent: parent, p_name: name };
  let id = await rpc("goya_hr_drive_folder_slot", args);
  if (id) {
    const folder = await getDriveItem(headers, id);
    if (folder?.parents?.includes(parent) && !folder.trashed && folder.name === name && folder.mimeType === folderType) return id;
    if (folder) throw new Error("A leave folder was moved or renamed. Ask the manager to check Google Drive.");
  } else {
    id = await rpc("goya_hr_drive_folder_slot", { ...args, p_candidate: await getDriveId(headers) });
  }
  const created = await fetch(driveApi + "/files?supportsAllDrives=true&fields=id", {
    method: "POST", headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ id, name, parents: [parent], mimeType: folderType }), signal: AbortSignal.timeout(10000),
  });
  if (created.ok) return id;
  if (created.status === 409) {
    const folder = await getDriveItem(headers, id);
    if (folder?.parents?.includes(parent) && !folder.trashed && folder.name === name && folder.mimeType === folderType) return id;
  }
  throw new Error("The leave folder could not be prepared in Google Drive.");
}

async function upload(file: File, employee: string, request: string, from: string, kind: string) {
  const type = acceptedTypes[file.type];
  if (!type || file.size > maxFile || !file.size) throw new Error("Choose a PDF, JPEG or PNG up to 5 MB.");
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (!type.signature.every((byte, index) => bytes[index] === byte)) throw new Error("The attachment does not match its file type.");
  const root = env("GOYA_LEAVE_DRIVE_FOLDER_ID");
  const account = env("GOYA_LEAVE_DRIVE_ACCOUNT").trim().toLowerCase();
  const clientId = env("GOYA_DRIVE_CLIENT_ID");
  const clientSecret = env("GOYA_DRIVE_CLIENT_SECRET");
  const refreshToken = env("GOYA_DRIVE_REFRESH_TOKEN");
  if (!root || !account || !clientId || !clientSecret || !refreshToken) throw new Error("Google Drive upload is awaiting setup.");
  const auth = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    body: new URLSearchParams({ client_id: clientId, client_secret: clientSecret,
      refresh_token: refreshToken, grant_type: "refresh_token" }),
    signal: AbortSignal.timeout(10000),
  });
  if (!auth.ok) throw new Error("Google Drive could not be reached. Retry your request.");
  const { access_token } = await auth.json();
  const headers = { Authorization: "Bearer " + access_token };
  const [who, rootInfo] = await Promise.all([
    fetch(driveApi + "/about?fields=user(emailAddress)", { headers, signal: AbortSignal.timeout(10000) }),
    getDriveItem(headers, root),
  ]);
  const owner = who.ok ? await who.json() : null;
  if (owner?.user?.emailAddress?.toLowerCase() !== account || rootInfo?.name !== "database" ||
      rootInfo?.mimeType !== folderType || rootInfo.trashed) {
    throw new Error("Google Drive account or database folder does not match the configured destination.");
  }
  const year = await ensureFolder(headers, root, from.slice(0, 4));
  const month = await ensureFolder(headers, year, from.slice(0, 7));
  const folder = await ensureFolder(headers, month, kind);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  const fingerprint = Array.from(digest, byte => byte.toString(16).padStart(2, "0")).join("");
  const id = await rpc("goya_hr_upload_slot", { p_staff: employee, p_id: request, p_drive: await getDriveId(headers), p_fingerprint: fingerprint });
  const boundary = "goya_" + crypto.randomUUID();
  const metadata = JSON.stringify({ id, name: "Leave-" + request + "." + type.ext, parents: [folder] });
  const body = new Blob([
    "--" + boundary + "\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n" + metadata +
      "\r\n--" + boundary + "\r\nContent-Type: " + file.type + "\r\n\r\n",
    file, "\r\n--" + boundary + "--\r\n",
  ]);
  const result = await fetch("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=id", {
    method: "POST", headers: { ...headers, "Content-Type": "multipart/related; boundary=" + boundary },
    body, signal: AbortSignal.timeout(25000),
  });
  if (result.status === 409) {
    const info = await getDriveItem(headers, id);
    if (info?.parents?.includes(folder) && !info.trashed) return id;
  }
  if (!result.ok) throw new Error("The attachment could not be saved in Google Drive. Retry your request.");
  return id;
}

function requestDate(value: string) {
  const parsed = Date.parse(value + "T00:00:00Z");
  return Number.isFinite(parsed) && new Date(parsed).toISOString().slice(0, 10) === value ? parsed : NaN;
}

async function notify(record: Record<string, string>, staffName: string) {
  const annual = record.kind === "Annual Leave";
  const sender = env("GOYA_LEAVE_FROM_EMAIL");
  const apiKey = env("GOYA_LEAVE_RESEND_KEY");
  if (!sender || !apiKey) return "Needs setup";
  const recipients = await rpc("goya_hr_worker_email_settings", {});
  const manager = recipients?.manager_email;
  if (!manager) return "Needs setup";
  if (annual && (!recipients?.owner_email || !recipients?.hr_email)) return "Needs setup";
  const to = annual ? [recipients.owner_email, recipients.hr_email] : [manager];
  const dateRange = record.requested_from + " to " + record.requested_to;
  const message = staffName + " submitted " + record.kind + " for " + dateRange +
    ".\nReview the request in GOYA Attendance Admin: " +
    (env("GOYA_LEAVE_ADMIN_URL") || "https://mehedih99.github.io/goya-portal/attendance.html") +
    "\nRequest ID: " + record.id;
  const result = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: "Bearer " + apiKey, "Content-Type": "application/json",
      "Idempotency-Key": "goya-leave/" + record.id },
    body: JSON.stringify({ from: sender, to,
      ...(annual ? { cc: [manager] } : {}), subject: "GOYA " + record.kind + " request", text: message }),
    signal: AbortSignal.timeout(10000),
  });
  return result.ok ? "Sent" : "Failed";
}

Deno.serve(async req => {
  const headers = {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, x-goya-session",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
  const reply = (status: number, data: unknown) => Response.json(data, { status, headers });
  if (!origin || req.headers.get("origin") !== origin) return reply(403, { error: "Origin denied" });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });
  const token = req.headers.get("x-goya-session");
  if (!token || token.length > 512) return reply(401, { error: "Sign in again." });
  const employee = await rpc("goya_hr_staff_identity", { p_token: token }).catch(() => null);
  if (!employee) return reply(401, { error: "Sign in again." });
  if (Number(req.headers.get("content-length")) > maxFile + 30_000) return reply(413, { error: "Attachment exceeds 5 MB." });
  try {
    const form = await req.formData();
    const id = String(form.get("id") ?? "");
    const kind = String(form.get("kind") ?? "");
    const from = String(form.get("from") ?? "");
    const to = String(form.get("to") ?? "");
    const reason = String(form.get("reason") ?? "").trim();
    const days = (requestDate(to) - requestDate(from)) / 86400000;
    if (!uuid.test(id) || !["Annual Leave", "Sick Leave", "Other Leave"].includes(kind) ||
        !(days >= 0 && days <= 365) || !reason || reason.length > 2000) {
      return reply(400, { error: "Check the leave type, dates and reason." });
    }
    const file = form.get("file");
    const driveId = file instanceof File && file.size ? await upload(file, employee.id, id, from, kind) : null;
    const record = await rpc("goya_hr_record_request", { p_staff: employee.id, p_id: id, p_kind: kind,
      p_from: from, p_to: to, p_reason: reason, p_drive: driveId });
    let email = record.email_state;
    if (email !== "Sent" && (Date.now() - Date.parse(record.created_at)) < 23 * 60 * 60 * 1000) {
      email = await notify(record, employee.name).catch(() => "Failed");
      await rpc("goya_hr_email_state", { p_id: id, p_state: email }).catch(() => {});
    }
    return reply(200, { id: record.id, email });
  } catch (error) {
    return reply(400, { error: error instanceof Error ? error.message : "Unable to submit leave." });
  }
});

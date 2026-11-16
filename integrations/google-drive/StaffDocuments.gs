// In Code.gs, after verifying the signature and parsing signed.payload as file:
// if (file.operation === 'staff-document-upload' || file.operation === 'staff-document-read')
//   return goyaStaffDocument(file);
const GOYA_DOCUMENT_CATEGORIES = {
  'emirates-id': 'Emirates ID',
  'contract': 'Employment Contract',
  'food-safety': 'Food Safety Certificate',
  'health-card': 'Health Card'
};

function goyaPrivateDocumentItem(item) {
  if (item.isTrashed() || item.getOwner().getEmail().toLowerCase() !== GOYA_OWNER ||
      item.getSharingAccess() !== DriveApp.Access.PRIVATE ||
      [...item.getEditors(), ...item.getViewers()].some(person => person.getEmail().toLowerCase() !== GOYA_OWNER)) {
    throw Error('Wrong private Drive destination');
  }
  return item;
}

function goyaStaffDocument(request) {
  const category = GOYA_DOCUMENT_CATEGORIES[request.category];
  const type = GOYA_TYPES[request.type];
  const writing = request.operation === 'staff-document-upload';
  if (!Object.prototype.hasOwnProperty.call(GOYA_DOCUMENT_CATEGORIES,request.category) ||
      !Object.prototype.hasOwnProperty.call(GOYA_TYPES,request.type) || !GOYA_UUID.test(request.id) ||
      !/^(?:GY-[0-9]{3,}|[A-Za-z0-9_-]{1,80}--[a-f0-9-]{36})$/.test(request.folder) ||
      !/^[0-9a-f]{64}$/.test(request.sha) ||
      !Number.isInteger(request.size) || request.size < 1 || request.size > GOYA_LIMIT ||
      (writing && (typeof request.bytes !== 'string' || request.bytes.length > Math.ceil(GOYA_LIMIT/3)*4)) ||
      (!writing && !/^[A-Za-z0-9_-]{10,}$/.test(request.driveId))) {
    return goyaJson({ok:false,code:'invalid'});
  }
  const verify = bytes => {
    if (bytes.length !== request.size || !type.header.every((byte,i) => (bytes[i] & 255) === byte)) {
      throw Error('Document content does not match');
    }
    const hash = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256,bytes)
      .map(byte => (byte & 255).toString(16).padStart(2,'0')).join('');
    if (hash !== request.sha) throw Error('Document fingerprint does not match');
    return bytes;
  };
  if (!writing) {
    const saved = goyaPrivateDocumentItem(DriveApp.getFileById(request.driveId));
    const bytes = verify(saved.getBlob().getBytes());
    return goyaJson({ok:true,bytes:Utilities.base64Encode(bytes)});
  }
  const bytes = verify(Utilities.base64Decode(request.bytes));
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const root = goyaPrivateDocumentItem(goyaFolder());
    const documents = goyaPrivateDocumentItem(goyaChild(root,'Staff Documents'));
    const employee = goyaPrivateDocumentItem(goyaChild(documents,request.folder));
    const folder = goyaPrivateDocumentItem(goyaChild(employee,category));
    const name = category + ' - ' + request.id + '.' + type.extension;
    const matches = folder.getFilesByName(name);
    if (matches.hasNext()) {
      const saved = goyaPrivateDocumentItem(matches.next());
      if (matches.hasNext()) throw Error('Duplicate document version');
      verify(saved.getBlob().getBytes());
      return goyaJson({ok:true,id:saved.getId()});
    }
    const saved = goyaPrivateDocumentItem(folder.createFile(Utilities.newBlob(bytes,request.type,name)));
    return goyaJson({ok:true,id:saved.getId()});
  } finally {
    lock.releaseLock();
  }
}

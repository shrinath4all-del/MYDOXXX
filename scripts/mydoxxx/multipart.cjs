const assert=require('node:assert/strict');

function buildUploadBody(metadata,data,boundary){
 assert(Buffer.isBuffer(data),'Upload data must be a Buffer');
 assert(/^[a-zA-Z0-9_-]+$/.test(boundary),'Invalid multipart boundary');
 const contentType=metadata.contentType||'application/octet-stream';
 assert(typeof contentType==='string'&&!/[\r\n]/.test(contentType),'Invalid object content type');
 return Buffer.concat([
  Buffer.from('--'+boundary+'\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'+JSON.stringify(metadata)+'\r\n--'+boundary+'\r\nContent-Type: '+contentType+'\r\n\r\n'),
  data,
  Buffer.from('\r\n--'+boundary+'--\r\n'),
 ]);
}

module.exports={buildUploadBody};

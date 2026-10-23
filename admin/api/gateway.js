import { randomUUID } from 'node:crypto';
function failure(code,message,status=502,upstreamStatus){return Object.assign(new Error(message),{gatewayCode:code,status,upstreamStatus});}
function backendUrl(){
 const value=process.env.BACKEND_API_URL;
 if(!value)throw failure('BACKEND_CONFIG_MISSING','عنوان الباك إند غير مضبوط في إعدادات Vercel.',503);
 let url;try{url=new URL(value);}catch{throw failure('BACKEND_CONFIG_INVALID','عنوان الباك إند في إعدادات Vercel غير صحيح.',503);}
 if(url.protocol!=='https:'||url.username||url.password||url.pathname!=='/'||url.search||url.hash)throw failure('BACKEND_CONFIG_INVALID','استخدم رابط HTTPS أساسيًا لخادم API.',503);
 return url.origin;
}
const allowed = [
 ['GET',/^\/(me|health|admin\/overview|institutions\/manage|courses|courses\/people|announcements|announcement-reports|groups|documents|polls|tournaments|services)$/],
 ['POST',/^\/(institutions|institutions\/select|courses|courses\/[^/]+\/sections|admin\/(users|verification|reports)\/[^/]+|announcements|polls\/[^/]+\/close)$/],
 ['PATCH',/^\/(sections\/[^/]+|institutions\/students\/[^/]+|announcements\/[^/]+)$/],
 ['DELETE',/^\/(announcements|documents|polls)\/[^/]+$/]
];
export function permitted(method,path){return allowed.some(([m,r])=>m===method&&r.test(path));}
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
 const send=(status,data)=>res.status(status).json(data);
 const host=req.headers.host;
 if(!['GET','POST','PATCH','DELETE'].includes(req.method))return send(405,{error:'طريقة غير مدعومة'});
 if(req.method!=='GET' && req.headers.origin!==`https://${host}` && !(host?.startsWith('localhost:')&&req.headers.origin===`http://${host}`)) return send(403,{error:'مصدر الطلب غير مسموح'});
 const path=req.query.path;
 if(typeof path!=='string' || path.includes('?') || path.includes('..') || path.includes('%') || path.includes('\\'))return send(400,{error:'مسار غير صالح'});
 const token=(req.headers.cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('__Host-stu_session='))?.slice(19);
 const cookie=(value,age)=>`__Host-stu_session=${value}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${age}`;
 async function call(p,method='GET',body,auth=token){
  const r=await fetch(backendUrl()+p,{method,redirect:'error',signal:AbortSignal.timeout(55000),headers:{'Content-Type':'application/json',...(auth?{Authorization:`Bearer ${auth}`}:{})},...(!['GET','HEAD'].includes(method)&&body!==undefined?{body:JSON.stringify(body)}:{})});
  let data;try{data=await r.json();}catch{throw failure('UPSTREAM_INVALID_RESPONSE','خادم API أعاد استجابة غير صالحة ('+r.status+').',502,r.status);}return {status:r.status,data};
 }
 try{
  let input;
  if(req.method!=='GET'){
   try{input=typeof req.body==='string'?(req.body.trim()?JSON.parse(req.body):{}):(req.body??{});}catch{return send(400,{error:'صيغة JSON غير صحيحة',code:'INVALID_JSON'});}
   if(!input||typeof input!=='object'||Array.isArray(input))return send(400,{error:'بيانات الطلب غير صحيحة',code:'INVALID_BODY'});
  }
  if(input&&Buffer.byteLength(JSON.stringify(input))>90000)return send(413,{error:'الطلب كبير'});
  if(path==='/ready'&&req.method==='GET'){
   const r=await call('/health','GET',undefined,null);
   return send(r.status===200&&r.data.ok===true?200:503,{ready:r.status===200&&r.data.ok===true,backend:backendUrl()});
  }
  if(path==='/login'&&req.method==='POST'){
   const r=await call('/auth/login','POST',{email:input?.email,password:input?.password},null);
   if(r.status!==200)return send(r.status,r.data);
   if(r.data.user?.role!=='admin'){await call('/auth/logout','POST',{},r.data.token);return send(403,{error:'هذا الحساب ليس مشرفًا. اطلب تفعيل صلاحية الإدارة من مشغّل الخادم.'});}
   res.setHeader('Set-Cookie',cookie(r.data.token,604800));return send(200,{user:r.data.user});
  }
  if(path==='/logout'&&req.method==='POST'){
   res.setHeader('Set-Cookie',cookie('',0));if(token)await call('/auth/logout','POST',{});return send(200,{ok:true});
  }
  if(!token)return send(401,{error:'سجّل الدخول أولًا'});
  const me=await call('/me');
  if(me.status>=500)return send(503,{error:'الخادم مشغول مؤقتًا. أعد المحاولة بعد قليل.'});
  if(me.status!==200||me.data.user?.role!=='admin'){res.setHeader('Set-Cookie',cookie('',0));return send(me.status===401?401:403,{error:'جلسة الإدارة غير متاحة'});}
  if(!permitted(req.method,path))return send(403,{error:'العملية غير متاحة في لوحة الإدارة'});
  if(path==='/me')return send(200,me.data);
  const r=await call(path,req.method,input);return send(r.status,r.data);
 }catch(e){
  const traceId=randomUUID().slice(0,8);
  const timeout=e.name==='TimeoutError'||e.name==='AbortError';
  const code=e.gatewayCode||(timeout?'UPSTREAM_TIMEOUT':e.name==='TypeError'?'UPSTREAM_NETWORK':'GATEWAY_INTERNAL');
  console.error('stu_gateway_failure',JSON.stringify({traceId,route:path,code,kind:e.name,upstreamStatus:e.upstreamStatus,cause:e.cause?.code}));
  return send(e.status||(timeout?504:502),{error:e.gatewayCode?e.message:timeout?'انتهت مهلة الاتصال بخادم API. أعد المحاولة.':'تعذر إتمام الاتصال بخادم API. أعد المحاولة أو أرسل رمز المتابعة للدعم.',code,traceId});
 }
}

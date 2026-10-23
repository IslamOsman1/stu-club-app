const BACKEND = 'https://stu-club-api.onrender.com';
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
  const r=await fetch(BACKEND+p,{method,redirect:'error',signal:AbortSignal.timeout(55000),headers:{'Content-Type':'application/json',...(auth?{Authorization:`Bearer ${auth}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
  const data=await r.json();return {status:r.status,data};
 }
 try{
  const input=typeof req.body==='string'?JSON.parse(req.body):req.body;
  if(input&&Buffer.byteLength(JSON.stringify(input))>90000)return send(413,{error:'الطلب كبير'});
  if(path==='/ready'&&req.method==='GET'){
   const r=await call('/health','GET',undefined,null);
   return send(r.status===200&&r.data.ok===true?200:503,{ready:r.status===200&&r.data.ok===true});
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
  if(me.status!==200||me.data.user?.role!=='admin'){res.setHeader('Set-Cookie',cookie('',0));return send(me.status===401?401:403,{error:'جلسة الإدارة غير متاحة'});}
  if(!permitted(req.method,path))return send(403,{error:'العملية غير متاحة في لوحة الإدارة'});
  if(path==='/me')return send(200,me.data);
  const r=await call(path,req.method,input);return send(r.status,r.data);
 }catch(e){return send(502,{error:'الخادم لم يستجب. قد تحتاج الخدمة المجانية دقيقة للاستيقاظ؛ أعد المحاولة.'});}
}

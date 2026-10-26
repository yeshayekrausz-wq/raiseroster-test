// Invoke with a device capability, never an admin JWT. Storage stays private.
import {createClient} from 'npm:@supabase/supabase-js@2.80.0';
const allowedOrigin='https://yeshayekrausz-wq.github.io';
Deno.serve(async req=>{
 const headers={'Access-Control-Allow-Origin':allowedOrigin,'Access-Control-Allow-Headers':'apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
 if(req.method==='OPTIONS')return new Response(null,{headers});
 if(req.method!=='POST')return new Response('Method not allowed',{status:405,headers});
 try{
  if(Number(req.headers.get('content-length'))>2048)throw Error('Invalid request');
  const text=await req.text();if(text.length>2048)throw Error('Invalid request');
  const {secret,student,media}=JSON.parse(text);if(!/^[a-f0-9]{64}$/.test(secret)||(!media&&!/^[0-9a-f-]{36}$/.test(student)))throw Error('Invalid request');
  const url=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!;
  const publicClient=createClient(url,anon,{auth:{persistSession:false}});
  if(media){
   if(typeof media!=='string'||media.length>250)return new Response('Unavailable',{status:403,headers});
   const {data:path,error}=await publicClient.rpc('rr_display_media_path',{p_secret:secret,p_path:media});
   if(error||!path)return new Response('Unavailable',{status:403,headers});
   const storage=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
   const {data,error:signedError}=await storage.storage.from('motivation-media').createSignedUrl(path,3600);
   if(signedError||!data)return new Response('Unavailable',{status:404,headers});
   return Response.json({url:data.signedUrl},{headers});
  }
  const {data:path,error}=await publicClient.rpc('rr_display_photo_path',{p_secret:secret,p_student:student});
  if(error||typeof path!=='string'||!path.startsWith('motivation-private:'))return new Response('Unavailable',{status:404,headers});
  const storagePath=path.slice('motivation-private:'.length);if(!storagePath||storagePath.includes('..'))throw Error('Invalid photo');
  const privateClient=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
  const {data:blob,error:downloadError}=await privateClient.storage.from('motivation-media').download(storagePath);
  if(downloadError||!blob||blob.size>25*1024*1024||!['image/png','image/jpeg','image/webp'].includes(blob.type))return new Response('Unavailable',{status:404,headers});
  return new Response(blob,{headers:{...headers,'Content-Type':blob.type,'X-Content-Type-Options':'nosniff'}});
 }catch{return new Response('Unavailable',{status:403,headers});}
});

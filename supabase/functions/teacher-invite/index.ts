import {createClient} from 'npm:@supabase/supabase-js@2.80.0';
const origin='https://yeshayekrausz-wq.github.io';
const redirectTo=origin+'/raiseroster-test/motivation/teacher/?setup=1';
Deno.serve(async req=>{
 const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Vary':'Origin'};
 if(req.method==='OPTIONS')return new Response(null,{headers});
 if(req.method!=='POST')return new Response('Method not allowed',{status:405,headers});
 try{
  const token=req.headers.get('authorization')||'';
  const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_ANON_KEY')!;
  const caller=createClient(url,key,{global:{headers:{Authorization:token}},auth:{persistSession:false}});
  const {data:user,error:authError}=await caller.auth.getUser();if(authError||!user.user)throw Error('Sign in as a school administrator.');
  const raw=await req.text();if(raw.length>256)throw Error('Invalid request');
  const {portal}=JSON.parse(raw);if(typeof portal!=='string'||!/^[0-9a-f-]{36}$/i.test(portal))throw Error('Invalid teacher');
  const {data:teacher,error}=await caller.rpc('rr_teacher_invite_claim',{p_portal:portal});if(error)throw error;
  const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
  const invited=await admin.auth.admin.inviteUserByEmail(teacher.email,{redirectTo});
  if(invited.error){
   if(!['email_exists','user_already_exists'].includes(invited.error.code||''))throw invited.error;
   // The class assignment already links this email. Preserve the existing password and session.
   return Response.json({sent:false,linked:true},{headers});
  }
  return Response.json({sent:true},{headers});
 }catch(e){return Response.json({error:e instanceof Error?e.message:String((e as {message?:string})?.message||'Invitation failed')},{status:400,headers});}
});

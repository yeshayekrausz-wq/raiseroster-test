export async function uploadMediaFile(db,path,file){
 const {data,error:authError}=await db.auth.getSession();if(authError||!data?.session)throw Error('Your sign-in expired. Sign in again before uploading.');
 const {error}=await db.storage.from('motivation-media').upload(path,file,{contentType:file.type,upsert:false});if(!error)return;
 const msg=String(error.message||error),status=String(error.statusCode||error.status||'');
 if(/fetch|network|load failed/i.test(msg))throw Error('Upload could not reach Supabase Storage. Check that your internet filter allows jqylxbqwznoohscjbxrx.supabase.co (including /storage/v1/). Your settings have not been saved. '+msg);
 if(/bucket.*not found/i.test(msg))throw Error('Media storage is not activated. Run Activate_Display_Media_Repair.sql in Supabase, then retry.');
 if(status==='403'||/row.level|policy|permission/i.test(msg))throw Error('Media upload permission was denied. Run Activate_Display_Media_Repair.sql and use a school admin account.');
 throw Error('Upload failed'+(status?' (HTTP '+status+')':'')+': '+msg);
}

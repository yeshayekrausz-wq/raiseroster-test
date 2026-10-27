export async function prepareStudentPhoto(file){
 if(!['image/jpeg','image/png','image/webp'].includes(file.type))throw Error('Choose a JPG, PNG or WebP picture.');
 if(file.size>80*1024*1024)throw Error('This picture is over 80 MB. Export it as a smaller JPG first.');
 let bitmap;try{bitmap=await createImageBitmap(file,{imageOrientation:'from-image'});}catch{throw Error('This picture could not be opened. Export it as JPG or PNG and try again.');}
 try{const scale=Math.min(1,1600/Math.max(bitmap.width,bitmap.height));const canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));const ctx=canvas.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',0.85));if(!blob)throw Error('Could not prepare this picture.');return new File([blob],file.name.replace(/\.[^.]*$/,'')+'.jpg',{type:'image/jpeg'});}finally{bitmap.close();}
}

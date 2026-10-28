import assert from 'node:assert/strict';
import {createHandler,verifySignature,commandBody} from '../supabase/functions/telnyx-phone/index.ts';
const pair=await crypto.subtle.generateKey('Ed25519',true,['sign','verify']);
const pub=Buffer.from(await crypto.subtle.exportKey('raw',pair.publicKey)).toString('base64');
const uuid='00000000-0000-4000-8000-000000000001';
const cfg={TELNYX_PUBLIC_KEY:pub,TELNYX_API_KEY:'test-only',TELNYX_APPLICATION_ID:'123',TELNYX_PHONE_NUMBER:'+12125550100',PHONE_ORGANIZATION_ID:uuid,PHONE_PROGRAM_ID:uuid,PHONE_ADMIN_USER_ID:uuid,PHONE_TEST_CALLERS:'+12125550101',SUPABASE_URL:'https://example.test',SUPABASE_SERVICE_ROLE_KEY:'test-only'};
const event={data:{id:uuid,event_type:'call.initiated',payload:{connection_id:'123',direction:'incoming',from:'+12125550101',to:'+12125550100',call_control_id:'abc'}}};
async function signed(body,when=Math.floor(Date.now()/1000)) {const raw=JSON.stringify(body);const sig=await crypto.subtle.sign('Ed25519',pair.privateKey,new TextEncoder().encode(`${when}|${raw}`));return new Request('https://example.test',{method:'POST',body:raw,headers:{'telnyx-timestamp':String(when),'telnyx-signature-ed25519':Buffer.from(sig).toString('base64')}});}
let calls=[];
const fake=async(url,opts)=>{calls.push({url,opts});return new Response(JSON.stringify(url.includes('/rpc/')?{action:'answer',command_id:uuid,state:uuid}:{}));};
const handler=createHandler(n=>cfg[n],fake);
assert.equal((await handler(await signed(event))).status,200);assert.equal(calls.length,2);
assert.equal(JSON.parse(calls[1].opts.body).command_id,uuid);
calls=[];
assert.equal((await handler(new Request('https://example.test',{method:'POST',body:JSON.stringify(event)}))).status,401);
assert.equal((await handler(await signed(event,Math.floor(Date.now()/1000)-600))).status,401);
assert.equal(calls.length,0);
for(const patch of [{from:'+12125550999'},{connection_id:'wrong'},{to:'+12125550999'},{direction:'outgoing'}]){
 assert.equal((await handler(await signed({data:{...event.data,payload:{...event.data.payload,...patch}}}))).status,200);
}
assert.equal(calls.length,0);
const failing=createHandler(n=>cfg[n],async(url)=>new Response('{}',{status:url.includes('/rpc/')?503:200}));
assert.equal((await failing(await signed(event))).status,503);
const failedCommand=createHandler(n=>cfg[n],async(url)=>url.includes('/rpc/')?new Response(JSON.stringify({action:'answer',command_id:uuid,state:uuid})):new Response('{}',{status:429}));
assert.equal((await failedCommand(await signed(event))).status,503);
const request=await signed(event);assert.equal(await verifySignature('changed',request.headers,pub),false);
assert.equal(commandBody({action:'gather_using_speak',command_id:uuid,state:uuid,prompt:'Test',digits:6}).maximum_digits,6);
assert.equal((await createHandler(()=>undefined,fake)(await signed(event))).status,503);
console.log('PASS: signatures, timestamp, route/caller scope, command formatting and retry responses');

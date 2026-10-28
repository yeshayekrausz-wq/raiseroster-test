// YKonnect Phone: real Telnyx calls, simulated card redemption. No reward writes.
// Intentionally standalone for Supabase's dashboard editor.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EVENTS = new Set(['call.initiated','call.answered','call.gather.ended','call.speak.ended','call.hangup']);
const decode64 = (s: string) => Uint8Array.from(atob(s), c => c.charCodeAt(0));
export async function verifySignature(raw: string, headers: Headers, publicKey: string, now = Date.now()) {
  try {
    const timestamp = headers.get('telnyx-timestamp') || '';
    if (!/^\d{10}$/.test(timestamp) || Math.abs(now / 1000 - Number(timestamp)) > 300) return false;
    const key = await crypto.subtle.importKey('raw', decode64(publicKey), {name:'Ed25519'}, false, ['verify']);
    return await crypto.subtle.verify('Ed25519', key, decode64(headers.get('telnyx-signature-ed25519') || ''), new TextEncoder().encode(`${timestamp}|${raw}`));
  } catch { return false; }
}
export function commandBody(result: any) {
  const base: any = {command_id:result.command_id};
  if (result.action === 'hangup') return base;
  base.client_state = btoa(result.state);
  if (result.action === 'answer') return base;
  Object.assign(base,{payload:result.prompt,voice:'male',language:'en-US',payload_type:'text'});
  if (result.action === 'gather_using_speak') Object.assign(base,{
    minimum_digits:1,maximum_digits:result.digits,maximum_tries:1,timeout_millis:30000,
    inter_digit_timeout_millis:10000,terminating_digit:'#',valid_digits:'0123456789',
  });
  return base;
}
export function createHandler(env: (name:string)=>string|undefined, fetcher: typeof fetch = fetch) {
  return async (request: Request): Promise<Response> => {
    const reply = (status:number,message:string) => new Response(JSON.stringify({message}),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
    if (request.method !== 'POST') return reply(405,'POST required');
    const names=['TELNYX_PUBLIC_KEY','TELNYX_API_KEY','TELNYX_APPLICATION_ID','TELNYX_PHONE_NUMBER','PHONE_ORGANIZATION_ID','PHONE_PROGRAM_ID','PHONE_ADMIN_USER_ID','PHONE_TEST_CALLERS','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY'];
    const cfg=Object.fromEntries(names.map(n=>[n,env(n)?.trim()]));
    if(names.some(n=>!cfg[n]) || !['PHONE_ORGANIZATION_ID','PHONE_PROGRAM_ID','PHONE_ADMIN_USER_ID'].every(n=>UUID.test(cfg[n]!))) return reply(503,'Phone setup incomplete');
    if (!/^\+\d{7,15}$/.test(cfg.TELNYX_PHONE_NUMBER!)) return reply(503,'Phone setup incomplete');
    let raw='';
    try {
      const reader=request.body?.getReader(); if(!reader) return reply(400,'Missing body');
      const chunks:Uint8Array[]=[]; let length=0;
      while(true){const {done,value}=await reader.read();if(done) break;length+=value.length;if(length>65536){await reader.cancel();return reply(413,'Body too large');}chunks.push(value);}
      const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
      raw=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
    }catch{return reply(400,'Invalid body');}
    if(!await verifySignature(raw,request.headers,cfg.TELNYX_PUBLIC_KEY!)) return reply(401,'Invalid signature');
    let event:any;
    try {event=JSON.parse(raw).data;}catch{return reply(400,'Invalid JSON');}
    if(!event || !UUID.test(event.id || '') || typeof event.event_type!=='string') return reply(400,'Invalid event');
    if(!EVENTS.has(event.event_type)) return reply(200,'Ignored');
    const p=event.payload;
    // Fail closed: only this app, inbound number, and explicitly permitted test callers.
    if(!p || String(p.connection_id)!==cfg.TELNYX_APPLICATION_ID || p.to!==cfg.TELNYX_PHONE_NUMBER || p.direction!=='incoming') return reply(200,'Route ignored');
    if(typeof p.call_control_id!=='string' || !p.call_control_id || p.call_control_id.length>512 || typeof p.from!=='string') return reply(400,'Invalid call');
    const testCallers=cfg.PHONE_TEST_CALLERS!.split(',').map(v=>v.trim()).filter(v=>/^\+\d{7,15}$/.test(v));
    if(!testCallers.includes(p.from)) return reply(200,'Caller outside test scope');
    let state='';
    try {if(p.client_state) state=atob(p.client_state);} catch {return reply(400,'Invalid state');}
    if(state && !UUID.test(state)) return reply(400,'Invalid state');
    const digits=p.digits ?? '';if(typeof digits!=='string'||digits.length>16) return reply(400,'Invalid digits');
    try {
      const response=await fetcher(`${cfg.SUPABASE_URL}/rest/v1/rpc/rr_telnyx_test_event`,{
        method:'POST',signal:AbortSignal.timeout(6000),headers:{'Content-Type':'application/json',apikey:cfg.SUPABASE_SERVICE_ROLE_KEY!,Authorization:`Bearer ${cfg.SUPABASE_SERVICE_ROLE_KEY}`},
        body:JSON.stringify({p_org:cfg.PHONE_ORGANIZATION_ID,p_program:cfg.PHONE_PROGRAM_ID,p_actor:cfg.PHONE_ADMIN_USER_ID,p_event:event.id,p_control:p.call_control_id,p_type:event.event_type,p_caller:p.from,p_digits:digits,p_state:state}),
      });
      if(!response.ok){console.error('phone database failure',event.id,response.status);return reply(503,'Please retry');}
      const result=await response.json();
      if(result.action){
        if(!['answer','hangup','speak','gather_using_speak'].includes(result.action)) throw new Error('Unexpected command');
        const command=await fetcher(`https://api.telnyx.com/v2/calls/${encodeURIComponent(p.call_control_id)}/actions/${result.action}`,{
          method:'POST',signal:AbortSignal.timeout(4000),headers:{Authorization:`Bearer ${cfg.TELNYX_API_KEY}`,'Content-Type':'application/json'},body:JSON.stringify(commandBody(result)),
        });
        if(!command.ok){console.error('phone command failure',event.id,command.status);return reply(503,'Please retry');}
      }
      // The result and command_id are persisted before sending. Never ACK failed delivery.
      return reply(200,'Processed');
    }catch{console.error('phone processing failure',event.id);return reply(503,'Please retry');}
  };
}
if (import.meta.main) Deno.serve(createHandler(name=>Deno.env.get(name)));

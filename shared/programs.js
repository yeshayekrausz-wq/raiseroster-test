// Menu settings are not data authorization. Existing backend permissions still apply.
export const PROGRAMS = Object.freeze([
  {key:'campaigns', name:'Campaigns', description:'Fundraising, contributions and projector.', ready:true, defaultVisible:true},
  {key:'motivation', name:'Motivation', description:'A group of motivation programs. Hatzlacha is being prepared.', ready:false, defaultVisible:true},
  {key:'library', name:'Library', description:'Books, student cards and lending. In preparation.', ready:false, defaultVisible:false},
]);
export const defaultPrograms = () => Object.fromEntries(PROGRAMS.map(p=>[p.key,p.defaultVisible]));
export function validatePrograms(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== PROGRAMS.length ||
      PROGRAMS.some(p=>typeof value[p.key] !== 'boolean')) throw new Error('Invalid program settings received. Reload and try again.');
  return {...value};
}
export function missingProgramBackend(error) {
  return error?.code === 'PGRST202' || error?.code === '42883';
}
export async function readSchoolMenu(client, organizationId) {
  const {data,error}=await client.rpc('rr_school_program_menu',{p_org:organizationId});
  if (error) {
    // Compatibility only for an undeployed RPC, never for permission/network failures.
    if(missingProgramBackend(error)) return {programs:defaultPrograms(),legacy:true};
    throw error;
  }
  return {programs:validatePrograms(data),legacy:false};
}

export async function resolveMembership(client, userId, requestedOrg) {
  const {data, error} = await client.from('organization_members')
    .select('organization_id,role').eq('user_id', userId);
  if (error) throw error;
  const rows = data || [];
  if (requestedOrg) {
    const match = rows.find(row => row.organization_id === requestedOrg);
    if (!match) throw new Error('You do not have membership in the selected school.');
    return match;
  }
  return rows.find(row => row.role === 'admin') || rows[0] || null;
}

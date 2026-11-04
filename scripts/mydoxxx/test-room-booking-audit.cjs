// Read-only evidence for the November 3 synthetic browser smoke test.
const C = require('./common.cjs');
const P = require('./test-lab-plan.cjs');
const L = require('./test-lab.cjs');
async function main() {
  const ctx = await L.adminContext();
  const result = await ctx.post('/' + P.BASE + '/documents:runQuery', {
    structuredQuery: {
      from: [{ collectionId: 'appointments' }],
      where: { fieldFilter: { field: { fieldPath: 'patientUid' }, op: 'EQUAL', value: { stringValue: 'mdxtestpatient2' } } }
    }
  });
  const rows = result.body.filter(x => x.document).map(x => {
    const d = x.document, f = d.fields;
    return { id: d.name.split('/').pop(), patientUid: f.patientUid?.stringValue,
      providerUid: f.doctorUid?.stringValue, status: f.status?.stringValue,
      type: f.type?.stringValue, isNurseRequest: f.isNurseRequest?.booleanValue, paymentStatus: f.paymentStatus?.stringValue,
      declinedBy: (f.declinedBy?.arrayValue?.values || []).map(x => x.stringValue),
      isBroadcast: f.isBroadcast?.booleanValue, createdAt: f.createdAt?.stringValue };
  }).filter(x => x.isNurseRequest && !x.id.startsWith('mdxtest'));
  console.log(JSON.stringify({syntheticNursingRows: rows}));
  C.assert(rows.length > 0, 'No browser-created nursing request found');
  C.assert(rows.some(x => x.providerUid === 'mdxtestnurse2' && x.status === 'Confirmed' && x.declinedBy.includes('mdxtestnurse')), 'Expected Nurse 1 decline and Nurse 2 confirmation');
  const evidence = { projectId: C.TARGET, databaseId: P.DATABASE, at: new Date().toISOString(),
    browserCreated: true, firestoreRecordsWrittenByAudit: 0, rows };
  await C.save('test-room-booking-audit-2026-11-03.json', evidence);
  console.log(JSON.stringify(evidence));
}
if (require.main === module) main().catch(() => { console.error('Read-only synthetic booking verification failed.'); process.exitCode = 1; });

const {test} = require('node:test'), assert = require('node:assert/strict');
const M = require('./test-lab-lab-tests.cjs');

const seeded = () => [
  {id: 'cbc', data: {name: 'CBC', price: 350, isActive: true, order: 1, mydoxSynthetic: true}, updateTime: 't1'},
  {id: 'ecg', data: {name: 'ECG', price: 450, isActive: true, order: 2, mydoxSynthetic: true}, updateTime: 't2'},
];

test('the catalogue is 21 tests: 8 neuro, 7 blood, 6 other', () => {
  const groups = Object.values(M.TESTS).map(t => t[0]);
  assert.equal(groups.length, 21);
  assert.deepEqual([groups.filter(g => g === 'neuro').length, groups.filter(g => g === 'blood').length, groups.filter(g => g === 'other').length], [8, 7, 6]);
});

test('on the seeded room: 19 tests are added, CBC and ECG only get their group', () => {
  const p = M.plan(seeded());
  assert.equal(p.filter(i => !i.exists).length, 19);
  const updates = Object.fromEntries(p.filter(i => i.exists).map(i => [i.path, i]));
  assert.deepEqual(updates['lab_tests/cbc'].patch, {category: 'blood', time: 30});
  assert.deepEqual(updates['lab_tests/ecg'].patch, {category: 'other', order: 1, time: 30});
  assert.equal(updates['lab_tests/cbc'].updateTime, 't1');
  assert.ok(!p.some(i => i.name === 'CBC (Complete Blood Count)'), 'no duplicate of the existing CBC');
});

test('a price already set is never changed, with or without a default price', () => {
  for (const price of [null, 500]) {
    for (const i of M.plan(seeded(), {price}).filter(i => i.exists)) assert.ok(!('price' in i.patch), i.path);
  }
});

test('without --price new tests have no price; with it they get that price', () => {
  assert.ok(M.plan(seeded()).filter(i => !i.exists).every(i => !('price' in i.patch)));
  assert.ok(M.plan(seeded(), {price: 500}).filter(i => !i.exists).every(i => i.patch.price === 500));
});

test('an existing test with no price gets the default price only when one is given', () => {
  const docs = [{id: 'eeg', data: {name: 'EEG'}, updateTime: 't'}];
  assert.equal(M.plan(docs).find(i => i.path === 'lab_tests/eeg').patch.price, undefined);
  assert.equal(M.plan(docs, {price: 700}).find(i => i.path === 'lab_tests/eeg').patch.price, 700);
});

test('new tests are marked synthetic, active and grouped; ids are simple slugs', () => {
  const eeg = M.plan(seeded()).find(i => i.name === 'EEG');
  assert.deepEqual(eeg, {path: 'lab_tests/eeg', name: 'EEG', exists: false,
    patch: {name: 'EEG', category: 'neuro', order: 1, isActive: true, time: 90, mydoxSynthetic: true, labMigration: 'lab-tests-v1'}});
  assert.equal(M.slug('PPBS (Post-Prandial Blood Sugar)'), 'ppbs_post_prandial_blood_sugar');
  assert.equal(M.slug('Lab - Blood Draw'), 'lab_blood_draw');
  for (const i of M.plan(seeded())) assert.match(i.path, /^lab_tests\/[a-z0-9_]+$/);
});

test('running it a second time changes nothing', () => {
  const first = M.plan(seeded(), {price: 500});
  const after = seeded().map(d => ({...d, data: {...d.data, ...(first.find(i => i.path === 'lab_tests/' + d.id)?.patch || {})}}));
  for (const i of first.filter(i => !i.exists)) after.push({id: i.path.split('/')[1], data: i.patch, updateTime: 'n'});
  assert.deepEqual(M.plan(after, {price: 500}), []);
});

test('a switched-off test stays switched off, and other tests are left alone', () => {
  const docs = [...seeded(), {id: 'x_ray', data: {name: 'X-Ray', isActive: false, price: 900}, updateTime: 't3'},
    {id: 'custom', data: {name: 'My own test', price: 100}, updateTime: 't4'}];
  const p = M.plan(docs);
  assert.ok(!('isActive' in p.find(i => i.path === 'lab_tests/x_ray').patch));
  assert.ok(!p.some(i => i.path === 'lab_tests/custom'));
});

test('two existing records for one test stop the plan', () => {
  const docs = [...seeded(), {id: 'ECG', data: {name: 'ecg'}, updateTime: 't5'}];
  assert.throws(() => M.plan(docs), /Two existing tests match "ECG"/);
});

test('--price accepts only sensible whole rupees', () => {
  assert.equal(M.parsePrice([]), null);
  assert.equal(M.parsePrice(['--price=500']), 500);
  for (const bad of ['--price=0', '--price=-5', '--price=abc', '--price=12.5', '--price=9999999']) assert.throws(() => M.parsePrice([bad]));
});

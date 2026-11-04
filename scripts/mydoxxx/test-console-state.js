/* Pure selection and panel lifecycle logic. No credentials or network access. */
(function(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.MyDoxConsoleState = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
  'use strict';
  const PROJECT = 'mydoxxx-dev-261102', DATABASE = 'mydoxxx-testing';
  const FAMILIES = Object.freeze({patient:'Patients',doctor:'Cardiologists',nurse:'Nurses',hospital:'Hospitals',ambulance:'Ambulances',care_physician:'Care physicians',technician:'Technicians',therapist:'Physiotherapists',agency_care:'Care agencies',agency_nurse:'Nursing agencies',agency_technician:'Technician agencies',agency_physio:'Physio agencies'});
  const PRESETS = Object.freeze({appointments:['patient','doctor','nurse','hospital'],doctors:['patient','doctor','doctor_2','doctor_3'],nurses:['patient_2','nurse','nurse_2','nurse_3'],emergency:['patient','hospital','doctor','ambulance'],team:['hospital','care_physician','care_physician_2','care_physician_3','agency_care'],technicians:['hospital','technician','technician_2','technician_3','agency_technician']});
  const keyFor = (family, person) => person === 1 ? family : family + '_' + person;
  function validateCatalog(data, cloudOrigin) {
    if (cloudOrigin !== undefined && cloudOrigin !== 'https://mydoxxx-live-test.netlify.app') throw Error('Unrecognised cloud test-room origin.');
    if (!data || data.projectId !== PROJECT || data.databaseId !== DATABASE || !Array.isArray(data.roles) || data.roles.length !== 36) throw Error('Expected the 36-account MYDOXXX test catalogue. Restart the updated local host.');
    const keys = new Set(), origins = new Set();
    const roles = data.roles.map(r => {
      if (!r || !Object.hasOwn(FAMILIES,r.family) || ![1,2,3].includes(r.person) || r.key !== keyFor(r.family,r.person) || keys.has(r.key) || r.uid !== 'mdxtest'+r.key.replaceAll('_','') || typeof r.label !== 'string' || r.label.length > 100) throw Error('Unexpected test identity in the catalogue.');
      const u = new URL(r.url);
      const validLocation = cloudOrigin ? u.origin === cloudOrigin && u.pathname === '/panel/' : u.protocol === 'http:' && u.hostname === '127.0.0.1' && Boolean(u.port) && u.pathname === '/' && !origins.has(u.origin);
      if (!validLocation || u.username || u.password || u.hash || u.searchParams.size !== 2 || u.searchParams.get('role') !== r.key || u.searchParams.get('autologin') !== '1') throw Error('Test account URL does not match the approved test room.');
      keys.add(r.key); origins.add(u.origin);
      // Copy only the public contract, even if a future server sends extra fields.
      return Object.freeze({key:r.key,label:r.label,family:r.family,person:r.person,uid:r.uid,url:u.href});
    });
    for (const family of Object.keys(FAMILIES)) for (const n of [1,2,3]) if (!keys.has(keyFor(family,n))) throw Error('A test family is missing an account.');
    return roles;
  }
  function selection(keys, catalogue) {
    const allowed = new Set(catalogue.map(r=>r.key));
    return Array.isArray(keys) ? [...new Set(keys.filter(k=>typeof k==='string' && allowed.has(k)))] : [];
  }
  function toggle(keys, key, on, catalogue) {
    return selection(on ? [...keys,key] : keys.filter(k=>k!==key),catalogue);
  }
  function replace(keys, oldKey, nextKey, catalogue) {
    if (keys.includes(nextKey)) return [...keys];
    return selection(keys.map(k=>k===oldKey?nextKey:k),catalogue);
  }
  function parseLayout(raw, catalogue) {
    try {
      const data = JSON.parse(raw);
      if (!data || data.version !== 2 || !Array.isArray(data.selected) || ![1,2,3,4].includes(data.columns)) return null;
      return {selected:selection(data.selected,catalogue),columns:data.columns};
    } catch (_) { return null; }
  }
  function serializeLayout(keys, columns, catalogue) {
    return JSON.stringify({version:2,selected:selection(keys,catalogue),columns:[1,2,3,4].includes(columns)?columns:2});
  }
  function reconcilePanels(panels, selected, adapter) {
    const desired = new Set(selected);
    for (const [key,panel] of panels) if (!desired.has(key)) { adapter.remove(panel); panels.delete(key); }
    selected.forEach((key,index)=>{
      if (!panels.has(key)) { const panel=adapter.create(key); panels.set(key,panel); adapter.insert(panel); }
      // CSS order only: moving an existing iframe in the DOM can reload it.
      adapter.order(panels.get(key),index);
    });
    return panels;
  }
  return {PROJECT,DATABASE,FAMILIES,PRESETS,keyFor,validateCatalog,selection,toggle,replace,parseLayout,serializeLayout,reconcilePanels};
});

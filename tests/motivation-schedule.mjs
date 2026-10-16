import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
const {scheduleActive}=await import('data:text/javascript;base64,'+Buffer.from(await readFile(new URL('../motivation/projector/schedule.js',import.meta.url),'utf8')).toString('base64'));
const config={timezone:'America/New_York',display_days:[1],display_start:'22:00',display_end:'02:00'};
assert.equal(scheduleActive(config,new Date('2026-10-20T03:00:00Z')),true); // Monday 23:00
assert.equal(scheduleActive(config,new Date('2026-10-20T05:00:00Z')),true); // Tuesday 01:00 follows Monday session
assert.equal(scheduleActive(config,new Date('2026-10-20T06:00:00Z')),false);
assert.equal(scheduleActive(config,new Date('2026-10-21T03:00:00Z')),false);
assert.equal(scheduleActive({...config,display_start:'08:00',display_end:'17:00'},new Date('2026-10-19T12:00:00Z')),true);
assert.equal(scheduleActive({...config,display_start:'08:00',display_end:'17:00'},new Date('2026-10-19T21:00:00Z')),false);
assert.equal(scheduleActive({...config,display_start:'00:00',display_end:'00:00'},new Date('2026-10-19T14:00:00Z')),true);
console.log('PASS display schedule: local timezone, same-day start/end boundaries, overnight continuation and disabled weekdays.');

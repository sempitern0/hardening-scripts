'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.join(__dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const html=read('index.html'),app=read('js/app.js');
const styles=read('css/workspace-ux.css'),sw=read('sw.js');
assert(html.includes('id="btn-pdf"')&&html.includes('Opciones PDF ↓'),'Toolbar must describe navigation, not claim to generate a PDF');
assert(html.includes('href="css/workspace-ux.css" media="screen"'),'UX fixes must be screen-only');
assert(sw.includes("'./css/workspace-ux.css'"),'UX stylesheet must work offline');
assert(app.includes('function goToPdfOptions()'),'PDF toolbar needs dedicated navigation handler');
assert(app.includes("byId('btn-pdf').addEventListener('click',goToPdfOptions)"));
assert(app.includes("heading.focus({preventScroll:true})"),'Destination must receive keyboard/screen-reader focus');
assert(app.includes("heading.scrollIntoView({"),'PDF button must scroll to the available choices');
assert(app.includes("prefers-reduced-motion: reduce"),'Scrolling must respect reduced motion');
assert(app.includes("workspace.querySelector('h1')"),'SPA page changes must focus the new heading');
assert(app.includes('id="delivery-options" aria-labelledby="delivery-options-title"'));
assert(app.includes('id="delivery-options-title" tabindex="-1"'));
assert(app.includes('class="report-delivery-grid"'),'PDF report types must be visually grouped');
assert(app.includes('class="report-delivery-danger"'),'Create-new-record action must be separated from export actions');
for(const id of ['delivery-executive-draft','delivery-executive-final','delivery-technical-draft','delivery-technical-final','retest-pdf','delivery-json']){
  assert(app.includes('id="'+id+'"'),'Export action removed: '+id);
}
for(const token of ['.topbar .actions', '#workspace .action-row', '.report-delivery-grid', '.report-delivery-danger', 'scroll-margin-block-start']){
  assert(styles.includes(token),'Missing layout/spacing rule '+token);
}
console.log('PASS accessible PDF navigation, toolbar spacing and mobile delivery choices');

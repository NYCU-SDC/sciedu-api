import assert from "node:assert/strict";
import fs from "node:fs";
import yaml from "js-yaml";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const read = (path) => fs.readFileSync(new URL(path, import.meta.url), "utf8");
const spec = yaml.load(read("../tsp-output/schema/openapi.1.0.0.yaml"));
const examples = JSON.parse(read("../docs/examples/material-editor.json"));
const schemas = spec.components.schemas;
const operation = (method, path) => {
  const op = spec.paths["/api" + path]?.[method.toLowerCase()];
  assert.ok(op, method + " " + path + " missing");
  return op;
};
const deref = (node) => node?.$ref ? node.$ref.split("/").slice(1).reduce((v, key) => v[key], spec) : node;
const properties = (node) => {
  node = deref(node);
  return Object.assign({}, ...(node.allOf ?? []).map(properties), node.properties ?? {});
};
const required = (node) => {
  node = deref(node);
  return [...(node.required ?? []), ...(node.allOf ?? []).flatMap(required)];
};
const json = (op, status = "200") => op.responses[status]?.content?.["application/json"]?.schema;
const added = [
  ["GET", "/courses/{id}/editor"], ["PUT", "/courses/{id}/editor"],
  ["POST", "/courses/{id}/copies"], ["GET", "/chat/presets"],
  ["PUT", "/experiments/{experimentId}/courses/{courseId}/replacement"], ["GET", "/chat/course"],
];
for (const [verb, path] of added) {
  const op = operation(verb, path);
  assert.ok(op.description);
  for (const status of ["401", "403", "500"]) assert.ok(op.responses[status]);
}

// Compile every affected operation's expected success explicitly. A valid error-only
// operation still compiles in TypeSpec, so compilation alone does not catch regressions.
const success = [
  ["GET", "/courses", "200"], ["POST", "/courses", "201"],
  ["GET", "/courses/{id}", "200"], ["PUT", "/courses/{id}", "200"], ["PUT", "/courses/{id}/status", "200"],
  ["GET", "/courses/{courseId}/pages", "200"], ["POST", "/courses/{courseId}/pages", "201"],
  ["PUT", "/courses/{courseId}/pages/order", "200"],
  ["GET", "/pages/{id}", "200"], ["PUT", "/pages/{id}", "200"], ["DELETE", "/pages/{id}", "204"],
  ["GET", "/pages/{id}/blocks", "200"], ["POST", "/pages/{id}/blocks", "201"],
  ["PUT", "/pages/{id}/blocks/{blockId}", "200"], ["DELETE", "/pages/{id}/blocks/{blockId}", "204"],
  ["PUT", "/pages/{id}/blocks/order", "200"],
  ["GET", "/content/text", "200"], ["GET", "/content/text/{id}", "200"], ["POST", "/content/text/batch", "200"],
  ["POST", "/content/text", "201"], ["POST", "/content/media", "201"], ["GET", "/content/media/{id}", "200"],
  ["DELETE", "/content/{id}", "204"],
  ["GET", "/questions", "200"], ["GET", "/questions/{id}", "200"], ["POST", "/questions", "201"],
  ["PUT", "/questions/{id}", "200"], ["DELETE", "/questions/{id}", "204"],
  ["PUT", "/experiments/{id}/status", "200"], ["GET", "/experiments/{id}/courses", "200"],
  ["POST", "/experiments/{id}/courses", "200"], ["DELETE", "/experiments/{id}/courses/{courseId}", "204"],
  ["GET", "/chat", "200"], ["POST", "/chat", "201"], ["GET", "/chat/{chatId}", "200"],
  ["DELETE", "/chat/{chatId}", "204"], ["POST", "/chat/{chatId}", "201"], ["GET", "/chat/stream/{messageId}", "200"],
  ...added.map(([v, p]) => [v, p, v === "POST" ? "201" : "200"]),
];
for (const [verb, path, status] of success) {
  const op = operation(verb, path);
  assert.ok(op.summary === undefined || op.summary === "/api" + path,
    "API navigation must use the resource path: " + verb + " " + path);
  assert.ok(op.responses[status], verb + " " + path + " lost success response " + status);
  assert.ok(op.security.some((entry) => Object.keys(entry).some((key) => spec.components.securitySchemes[key]?.name === "access_token")));
  for (const [code, response] of Object.entries(op.responses)) {
    if (Number(code) >= 400) assert.deepEqual(Object.keys(response.content), ["application/problem+json"], verb + " " + path + " error media type");
  }
}
for (const [verb, path] of [
  ["POST", "/courses"], ["POST", "/content/text"], ["POST", "/content/media"], ["POST", "/questions"],
  ["PUT", "/courses/{id}/editor"], ["POST", "/courses/{id}/copies"],
  ["PUT", "/experiments/{experimentId}/courses/{courseId}/replacement"],
]) {
  const header = operation(verb, path).parameters.map(deref).find((p) => p.name === "Idempotency-Key");
  assert.ok(header?.required, verb + " " + path + " requires idempotency key");
  assert.equal(deref(header.schema).format, "uuid");
}
assert.equal(operation("PUT", "/courses/{id}/status").parameters.map(deref).find((p) => p.name === "Idempotency-Key").required, false);
assert.ok(!required(schemas["Courses.UpdateCourseStatusRequest"]).includes("expectedRevision"), "legacy status body stays accepted");
for (const name of ["Courses.Course", "Pages.Page"]) {
  for (const field of ["presentation", "revision"]) assert.ok(!required(schemas[name]).includes(field));
}
assert.equal(properties(schemas["Experiments.ExperimentCourseAssignment"]).course.$ref, "#/components/schemas/Courses.Course", "student experiment list must not require management-only preset projection");
assert.ok(!required(schemas["Courses.Course"]).includes("preset"));
assert.deepEqual(schemas["Pages.PageBlockType"].enum.toSorted(), ["MEDIA", "QUESTION", "TEXT"]);
assert.deepEqual(schemas["Materials.Stage"].enum.toSorted(), ["initial", "argumentation", "simulation", "final", "ccm-initial", "ccm-observation", "ccm-discussion", "ccm-final"].toSorted());
assert.deepEqual(schemas["Materials.SimulationId"].enum.toSorted(), ["dark-room-v1", "ccm-heart-v1", "ccm-marrow-v1"].toSorted());
assert.equal(operation("POST", "/chat").requestBody.required, false);
assert.ok(operation("POST", "/chat").responses["200"]);
assert.ok(properties(schemas["Chat.GeneralChatResult"]).chatID);
assert.ok(properties(schemas["Chat.CourseChatResult"]).chatId);
assert.ok(properties(schemas["Chat.Message"]).errorCode);
assert.equal(operation("GET", "/chat/course").parameters.filter((p) => p.in === "query" && p.required).length, 3);
assert.ok(operation("GET", "/chat/stream/{messageId}").responses["200"].content["text/event-stream"]);
assert.deepEqual(Object.keys(schemas["Chat.StreamEvent"].discriminator.mapping).sort(), ["agent_end", "agent_start", "cast", "delta", "done", "error", "part_end", "part_start"]);
for (const key of ["parts", "characters", "agentRuns"]) {
  assert.ok(properties(schemas["Chat.Message"])[key], "preserve origin/main message snapshot: " + key);
  assert.ok(!required(schemas["Chat.Message"]).includes(key));
}
assert.ok(required(schemas["Chat.DeltaEvent"]).includes("index"));
assert.ok(required(schemas["Chat.PartEndEvent"]).includes("part"));
assert.deepEqual(required(schemas["Chat.AgentRun"]).sort(), ["agent", "id"]);
for (const path of ["/api/progress/me", "/api/users/me/grade", "/api/users/{id}/grade"]) {
  assert.ok(spec.paths[path], "preserve current origin/main API: " + path);
}
function verifyEnglishDocs(node) {
  if (!node || typeof node !== "object") return;
  for (const [key, value] of Object.entries(node)) {
    if (["example", "examples"].includes(key)) continue; // Educational sample content may be localized.
    if (["summary", "description", "title"].includes(key) && typeof value === "string") {
      assert.ok(!/[\u3400-\u9fff]/u.test(value), "API documentation must keep English entry points: " + value.slice(0, 100));
    }
    verifyEnglishDocs(value);
  }
}
verifyEnglishDocs(spec);
for (const status of ["409", "503"]) assert.ok(operation("POST", "/chat/{chatId}").responses[status]);
assert.equal(operation("GET", "/content/media/{id}").responses["200"].headers["X-Content-Type-Options"].schema.enum[0], "nosniff");
assert.ok(operation("POST", "/content/media").requestBody.content["multipart/form-data"]);
assert.ok(!spec.paths["/api/pages/{id}/editor"]);
for (const node of ["Courses.Course", "Pages.Page", "Experiments.Experiment"]) {
  for (const field of ["firstUsedAt", "firstActivatedAt"]) assert.ok(!properties(schemas[node])[field], "internal markers stay internal");
}
const seen = new Set();
function verifyPublic(node) {
  if (!node || typeof node !== "object") return;
  if (node.$ref) {
    if (seen.has(node.$ref)) return;
    seen.add(node.$ref);
    return verifyPublic(deref(node));
  }
  for (const [key, value] of Object.entries(node.properties ?? {})) {
    assert.ok(!["correctAnswer", "referenceAnswer", "answers", "chatHistory", "password", "uploader", "filePath"].includes(key), "editor leaks " + key);
    verifyPublic(value);
  }
  for (const key of ["allOf", "anyOf", "oneOf"]) for (const child of node[key] ?? []) verifyPublic(child);
  verifyPublic(node.items);
}
verifyPublic(schemas["Materials.EditorDocument"]);

const ajv = new Ajv2020({strict: false, allErrors: true});
addFormats(ajv);
ajv.addFormat("int32", {type: "number", validate: (n) => Number.isInteger(n) && n >= -2147483648 && n <= 2147483647});
ajv.addFormat("int64", {type: "number", validate: Number.isInteger});
ajv.addSchema({$id: "urn:sciedu:contract", components: spec.components});
const validator = (name) => ajv.compile({$ref: "urn:sciedu:contract#/components/schemas/" + name});
const save = validator("Materials.SaveDocumentRequest");
let schemaCases = 0;
function check(name, value, valid, validate = save) {
  assert.equal(validate(value), valid, name + ": " + ajv.errorsText(validate.errors));
  schemaCases++;
}
for (const [name, fixture] of Object.entries(examples)) check(name + " example", fixture, true);
for (const fixture of schemas["Materials.SaveDocumentRequest"].examples) check("emitted TypeSpec example", fixture, true);
for (const fixture of Object.values(examples)) {
  const emitted = schemas["Materials.SaveDocumentRequest"].examples.find((x) =>
    x.document.code === fixture.document.code && x.document.pages.length === fixture.document.pages.length);
  assert.deepEqual(emitted, fixture, "emitted request example differs from checked-in fixture");
}
const editorResponse = validator("Materials.EditorDocument");
check("editor response fixture", JSON.parse(read("../docs/examples/material-editor-response.json")), true, editorResponse);
for (const fixture of schemas["Materials.EditorDocument"].examples) check("emitted editor response", fixture, true, editorResponse);
assert.deepEqual(schemas["Materials.EditorDocument"].examples[0], JSON.parse(read("../docs/examples/material-editor-response.json")));
function bad(name, mutate, fixture = examples.general) {
  const input = structuredClone(fixture);
  mutate(input);
  check(name, input, false);
}
bad("read-only resources", (x) => {x.document.resources = {};});
bad("read-only status", (x) => {x.document.status = "PUBLISHED";});
bad("server course id", (x) => {x.document.id = x.document.pages[0].id;});
bad("client revision", (x) => {x.document.revision = 5;});
bad("missing expected revision", (x) => {delete x.expectedRevision;});
bad("zero revision", (x) => {x.expectedRevision = 0;});
bad("unknown schema version", (x) => {x.document.schemaVersion = 1;});
bad("empty course title", (x) => {x.document.title = "";});
bad("unknown stage", (x) => {x.document.pages[0].presentation.stage = "invented";});
bad("unknown simulation", (x) => {x.document.pages[0].presentation.nodes[0].children[1].simulationId = "https://example.com";}, examples.ccm);
bad("grid missing layout", (x) => {delete x.document.pages[0].presentation.nodes[0].layout;});
bad("grid span", (x) => {x.document.pages[0].presentation.nodes[0].layout.colSpan = 5;});
bad("template layout forbidden", (x) => {x.document.pages[0].presentation.nodes[0].layout = {colSpan: 12, rowSpan: 1};}, examples.sciarg);
bad("child layout forbidden", (x) => {x.document.pages[0].presentation.nodes[0].children[0].layout = {colSpan: 12, rowSpan: 1};});
bad("nested reading group", (x) => {x.document.pages[0].presentation.nodes[0].children[0] = structuredClone(x.document.pages[0].presentation.nodes[0]);});
bad("TEXT required true", (x) => {x.document.pages[0].blocks[0].required = true;});
bad("block invalid type", (x) => {x.document.pages[0].blocks[0].type = "SIMULATION";});
bad("single reference cardinality", (x) => {x.document.pages[1].presentation.nodes[0].references.push(structuredClone(x.document.pages[1].presentation.nodes[0].references[0]));});
bad("text-choice cardinality", (x) => {x.document.pages[0].presentation.nodes[1].input.options = ["only"];});
bad("invalid UUID", (x) => {x.document.pages[0].id = "bad";});
bad("too many pages", (x) => {x.document.pages = Array(501).fill(x.document.pages[0]);});
bad("too many context IDs", (x) => {x.document.pages[0].presentation.contextTextIds = Array(101).fill(x.document.pages[0].id);});
const preset = validator("Materials.PresetState");
check("unselected preset", {selection: "UNSELECTED", presetId: null, availability: null}, true, preset);
check("removed preset", {selection: "SELECTED", presetId: "original", availability: "REMOVED"}, true, preset);
check("invalid preset pairing", {selection: "UNSELECTED", presetId: "original", availability: "AVAILABLE"}, false, preset);
const createChat = validator("Chat.CreateChatRequest");
check("legacy empty chat", {}, true, createChat);
check("partial course context", {courseContext: {courseId: "00000000-0000-4000-8000-000000000001"}}, false, createChat);
check("legacy publish", {status: "PUBLISHED"}, true, validator("Courses.UpdateCourseStatusRequest"));
check("SSE business error", {type: "error", error: "preset unavailable", code: "COURSE_CHAT_PRESET_UNAVAILABLE"}, true, validator("Chat.StreamEvent"));
check("origin/main delta", {type: "delta", index: 0, delta: "hello"}, true, validator("Chat.StreamEvent"));
check("delta index remains required", {type: "delta", delta: "hello"}, false, validator("Chat.StreamEvent"));
check("part_end final part remains required", {type: "part_end", index: 0}, false, validator("Chat.StreamEvent"));
check("untyped legacy delta is not reintroduced", {delta: "hello", isFinished: false}, false, validator("Chat.StreamEvent"));
console.log(`Material contract checks passed: 6 new + 38 existing operations; ${schemaCases} JSON Schema cases, auth, idempotency, error media types, privacy and legacy compatibility.`);

const mockBase = process.argv[2];
if (mockBase) {
  const id = "00000000-0000-4000-8000-000000000001";
  let httpCases = 0;
  async function request(name, method, path, body, status, prefer = status, key = true) {
    const response = await fetch(mockBase + "/api" + path, {
      method,
      headers: {Cookie: "access_token=contract-test", Prefer: "code=" + prefer,
        ...(key ? {"Idempotency-Key": id} : {}), ...(body === undefined ? {} : {"Content-Type": "application/json"})},
      ...(body === undefined ? {} : {body: JSON.stringify(body)}),
    });
    const text = await response.text();
    assert.equal(response.status, status, name + ": " + text.slice(0, 500));
    httpCases++;
    return response;
  }
  const path = "/courses/" + id + "/editor";
  for (const [name, input] of Object.entries(examples)) await request(name, "PUT", path, input, 200);
  // Prism selects declared 422 for schema validation failures on this operation.
  // Backend malformed requests/missing headers still follow the documented 400.
  await request("missing idempotency", "PUT", path, examples.empty, 422, 200, false);
  await request("invalid revision", "PUT", path, {...examples.empty, expectedRevision: 0}, 422, 200);
  await request("editor read", "GET", path, undefined, 200);
  await request("copy", "POST", "/courses/" + id + "/copies", {expectedSourceRevision: 1, code: "copy", title: "副本"}, 201);
  await request("presets", "GET", "/chat/presets", undefined, 200);
  await request("replace", "PUT", "/experiments/" + id + "/courses/" + id + "/replacement", {replacementCourseId: id}, 200);
  await request("lookup", "GET", "/chat/course?experimentId=" + id + "&courseId=" + id + "&pageId=" + id, undefined, 200);
  await request("missing lookup scope", "GET", "/chat/course?courseId=" + id, undefined, 400, 200);
  await request("general chat empty body", "POST", "/chat", undefined, 201);
  await request("course chat", "POST", "/chat", {courseContext: {experimentId: id, courseId: id, pageId: id}}, 201);
  await request("existing course chat", "POST", "/chat", {courseContext: {experimentId: id, courseId: id, pageId: id}}, 200);
  await request("legacy status", "PUT", "/courses/" + id + "/status", {status: "PUBLISHED"}, 200, 200, false);
  const failed = await request("chat unavailable", "POST", "/chat/" + id, {content: "test", preset: "ignored-for-course"}, 503);
  assert.equal(failed.headers.get("content-type").split(";")[0], "application/problem+json");
  console.log(`Prism passed ${httpCases} HTTP cases. Mocks do not verify authorization, DB transactions, permanent locks, reference graphs or upstream availability.`);
}

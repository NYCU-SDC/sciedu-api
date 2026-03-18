import "@typespec/http";
import "@typespec/versioning";
import "./service/problems.tsp";
import "./service/healthz.tsp";
import "./service/auth.tsp";
import "./service/users.tsp";
import "./service/questions.tsp";
import "./service/chat.tsp";

using Http;
using Versioning;

@service(#{ title: "SciEdu API" })
@server("https://dev.sciedu.sdc.nycu.club", "SciEdu server endpoint")
@versioned(Versions)
@route("/api")
namespace SciEdu;

enum Versions {
  v1: "1.0.0",
}

@format("uuid")
scalar uuid extends string;

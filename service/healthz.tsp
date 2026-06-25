import "@typespec/http";

using Http;

@tag("Healthz")
namespace SciEdu.Healthz {
  @route("/healthz")
  @get
  op checkHealthz(): {
    @statusCode statusCode: 200;
    @body body: { status: "OK" };
  } | {
    @statusCode statusCode: 404;
  };
}

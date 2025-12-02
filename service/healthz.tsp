import "@typespec/http";

using Http;

@tag("Healthz")
namespace SciEdu.Healthz {
  @route("/healthz")
  @get
  op checkHealthz(): {
    @statusCode statusCode: 200;
  } | {
    @statusCode statusCode: 404;
  };
}

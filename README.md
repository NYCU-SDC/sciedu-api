# SciEdu API

SciEdu API documentation.

## Dependencies

Please install [Node.js](https://nodejs.org/) and [pnpm](https://pnpm.io/) first.

pnpm installation:

```bash
npm install --global corepack@latest
corepack enable pnpm
```

## Install Packages

```bash
pnpm i
```

## Build

You need to compile after editing to preview, compiling automatically runs format, compile and yaak for you.

```bash
pnpm build
```

## Local Preview

Build and serve the generated API documentation locally:

```bash
pnpm preview:build
```

Then open <http://localhost:3000>. The preview server is powered by
[`http-server`](https://www.npmjs.com/package/http-server), listens only on the
local machine, and disables browser caching so rebuilt OpenAPI output is shown
after a refresh.

If the output has already been built, start the preview server without building
again:

```bash
pnpm preview
```

To run a mock API from the generated OpenAPI document instead, use
`pnpm start`; Prism listens on <http://localhost:4010>.

<details>

<summary>Other Commands</summary>

### Format Check

```bash
pnpm format
```

### Compilation

#### OpenAPI

```bash
pnpm compile
```

#### Yaak

```bash
pnpm yaak
```

> You need to compile OpenAPI before compiling Yaak

### Clean Compiled Files

```bash
pnpm clean
```

</details>

## Output Files

The OpenAPI output is written to `tsp-output/schema/openapi.1.0.0.yaml`. You can preview it using:

- [Scalar](https://scalar.dev/api-reference/) - Run `pnpm preview` and open <http://localhost:3000>.
- [Swagger UI](https://nycu-sdc.github.io/sciedu-api/) - Run `pnpm preview` and open <http://localhost:3000/swagger.html>.
- [Prism](https://prismjs.com/) - For API documentation preview and testing. Run `pnpm start` and open <http://localhost:4010>.
- [Yaak](https://yaak.app/) - Import the `yaak` folder.

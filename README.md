# run-these

Scripts and commands to run by hand. Each one is a single file at the top of this folder.

## Get it

```
git clone https://github.com/jorden-parker/run-these.git
cd run-these
ln -s ../../.githooks/commit-msg .git/hooks/commit-msg
```

The last line turns on the commit message check for this clone. Git does not copy hooks, so run it once per clone.

## Scripts

| Script | What it does |
| --- | --- |
| `proxy-stream-check` | Sends one small request to an Anthropic API proxy twice, without `stream` and with `"stream": true`, and prints both responses. Shows whether the proxy treats the two differently. |

### proxy-stream-check

```
./proxy-stream-check <model id>
```

It reads the proxy address from `ANTHROPIC_BASE_URL`, and the credential from `ANTHROPIC_AUTH_TOKEN` (sent as a bearer token) or `ANTHROPIC_API_KEY` (sent as `x-api-key`). The model id can come from `ANTHROPIC_MODEL` instead of the argument.

To supply those values in a file:

```
cp .env.example .env
chmod 600 .env
```

Then fill in `.env`. The script reads the `.env` beside it, and a value there wins over the same variable in the environment. A model id given as the argument wins over both. If your credential is an API key, replace the `ANTHROPIC_AUTH_TOKEN` line with `ANTHROPIC_API_KEY="your-key"`. If you have neither, delete that line: the script then sends the requests with no credential and says so.

Git ignores `.env`, so the token cannot be committed. With `.env` filled in, the script needs no argument:

```
./proxy-stream-check
./proxy-stream-check claude-haiku-5-5
```

Read the result like this:

- 429 on the first response and 200 on the second: the proxy refuses non-streaming requests.
- The same status on both: streaming is not what the proxy looks at. The body of the error says what is.

The credential goes to `curl` on standard input, so it never appears in the process list. The output includes the proxy's response headers; remove anything internal before you share it.

## Commit messages

Every commit follows [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary`, with the scope optional. `.githooks/commit-msg` rejects anything else.

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

## Tests

```
./check
```

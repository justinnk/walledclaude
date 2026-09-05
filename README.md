# Walled Claude: A Basic Claude Code Docker Sandbox

> :warning: **CAUTION:** This is a hobby project by someone not specialized in security research and provided as-is without any warranties. I coded this in a day based on some code I found on the internet, and refined it over time, also with some help from Claude. It is not a finished product, but here for you to inspect and adapt for your own use. That being said, I have used it myself a lot without any obvious issues so far. If you have any suggestions or found a problem, you are welcome to open an issue.

A relatively lightweight and convenient sandbox for Claude Code based on Docker (containerization) and Squid (proxy).
Designed to let it run in auto mode without breaking your system while still being convenient and retaining most of its features;
NOT designed to be fully fool proof and hardened, e.g., NOT designed to experiment with letting an LLM go rogue on purpose.

The `walledclaude` command should only be used inside version-controlled folders with a remote copy on some server (e.g., GitHub repositories), so any accidental deletions (I actually observed this behavior in a long running session with many subagents) can be rolled back. By default, the `ssh` keys stored in `~/.ssh` will not be accessible to Claude, so that it can change the local history, but never push any changes.

The sandbox can also be easily adjusted to contain other agentic harnesses, such as [pi](https://github.com/earendil-works/pi) or [opencode](https://github.com/anomalyco/opencode) that support arbitrary LLMs.

This is an extension of the `safeclaude` command described by Tim Walls in his [Blog post](https://snowgoons.ro/posts/2026-05-20-running-claude-code-in-a-docker-container/). I decided to swap the word "safe" to avoid a false sense of security (it is *much* more secure than vanilla Claude Code, but not "totally" secure; see below for the [threat model](#threat-model) considered).


## :vs: What you gain over...

- ...Claude's Bash sandbox: isolation of the whole Claude Code process, not just Bash; explicit control on what Claude can access (via volume mounts); network egress control separated from main container (out of the agent's reach).
- ...a devcontainer: one-time setup and use in any folder without per-repository configuration. Pre-hardened container (e.g., with dropped capabilities); network egress control separated from main container (out of the agent's reach).
- ...a VM: less overhead and easier setup/configuration.

However, the approach of `walledclaude` is only one point in the above range. What you should use depends on your threat model (see [Threat Model](#threat-model)). See also Claude Code's [documentation on isolation](https://code.claude.com/docs/en/sandbox-environments).

Other takes on the same problem that were brought to my attention:
- [codingseal](https://github.com/TorbenGl/codingseal) is a more heavyweight option using rootless Podman and with GPU support, but without egress proxy.
- [claude-code-sandbox](https://github.com/FoamoftheSea/claude-code-sandbox) is a very similar project, also relying on Docker and a Squid proxy for egress control. It guards against a very similar threat model as well.
- [claude-sbx](https://github.com/tobby-lie/claude-sbx) uses Docker's microVM instead of a standard docker container. This means that the sandbox does not even share the same Linux kernel as the host.

## :cd: Prerequisites

- Linux OS. MacOS should work too, but is untested.
- `docker`
- Your user needs to be in the `docker` group; `sudo usermod -aG docker <username>`
- `docker-buildx` (e.g. `sudo pacman -S docker-buildx`); this is required by newer docker versions to build custom images.
- `curl` (to look up the current Claude Code version)

## :arrow_forward: Install and Use

Run `./build.sh` to build the docker container (this can take a around four minutes when you first run it). It will be stored for reuse in your local image list.
Source `walledclaude.sh` in your shell config, such as `~/.zshrc` or `~/.bashrc`, using its *full path*: `source ~/path/to/walledclaude/walledclaude.sh`. This makes the command usable in all your terminal sessions.
Then, in any directory, run `walledclaude`. This will launch the "walled" Claude container and put you right into a Claude Code session. The startup time will be a bit longer upon first launch, as the Squid image is pulled. Subsequent startups will be much quicker.

You can also pass a different command to run inside the sandbox instead of Claude Code, e.g. `walledclaude bash` to get a shell, `walledclaude python3` for a REPL, or another agentic harness you added to the `Dockerfile`. If the first argument is not the name of a program installed in the container, everything is handed to Claude Code instead, so its flags and subcommands keep working as usual: `walledclaude --resume`, `walledclaude mcp list`.

### Configuration

You can configure some things about the sandbox using environment variables.
Set them using `export NAME=value` in your shell configuration.

| Variable               | Default              | Meaning                                                                                     |
| ---------------------- | -------------------- | ------------------------------------------------------------------------------------------- |
| `WALLEDCLAUDE_VERSION` | newest build         | Claude Code version, e.g. `2.0.14`. When changing, rerun `./build.sh`.                      |
| `WALLEDCLAUDE_CPUS`    | host cores minus one | CPU limit for the container. One core is left to the host so your machine stays responsive. |
| `WALLEDCLAUDE_MEMORY`  | `4g`                 | Memory limit for the container.                                                             |

### Update

To update the Claude version, just run `./build.sh` again.

<a id="threat-model"></a>

## :imp: Threat Model

These are the attack vectors we consider. Most of these things are obviously somewhat addressed by the Claude Code harness itself, for example through the auto classifier and training of models to avoid prompt injection, but we here take some additional measures to achieve a more definite protection.

- Claude Code may execute unwanted commands to alter the host system, like `rm -rf` or escape to disallowed paths using `cd` (addressed through containerization)
- Prompt injection
  - Claude may read a file that instructs it to take malicious or destructive actions (addressed through containerization)
  - Claude may search the web or fetch a website that contains malicious prompts that instruct it to
    - execute malicious or destructive commands (addressed through containerization)
    - leak or exfiltrate any data on the host via (additional) http requests (addressed through proxy and domain whitelist)

## :black_square_button: Trust Boundary and Attack Surface

The default network trust boundary configured in `squid.conf` is minimal: Anthropic and its domains `*.anthropic.com`, `*.claude.ai`, and `*.claude.com` are trusted (including all their subdomains).
You can adjust this by editing `squid.conf` to include other trusted websites. Keep in mind any attacker owning/with internal access to these sites could steal data from your attack surface.
Attack surface: The following are freely accessible to the containerized Claude Code that launches with the `walledclaude` command and implicitly trusted by you when you launch `walledclaude`.
- The folder you are running `walledclaude` in, including all subfolders and all files.
- The file `~/.walledclaude.json` in your home folder
- The folder `~/.walledclaude/` in your home folder
- Services listening on your host, but only those bound to the docker internal network address. Look up its address with `docker network inspect claude-sandbox | grep -i -w gateway`; it is typically something like `172.19.0.1` and can change when the network is recreated. Traffic over this address bypasses the squid proxy and can also use other protocols than HTTPS. This is useful for local MCP servers (see below). Programs that honor `HTTP_PROXY`/`HTTPS_PROXY` will send requests for it through squid, where they are denied unless you add a rule (see the Zotero MCP example in `squid.conf`). Services bound to `127.0.0.1` are explicitly not accessible.

Nothing else can be accessed from inside.

### :grey_exclamation: Things to Consider

Given the above, these are things you should keep in mind:
- Do *never* launch walledclaude in a directory containing secrets.
  - also Claude Code is very good at analyzing large volumes of data. It is very easy to leak things like your host's file system layout, for example if the current folder includes a Python virtual environment with symlinks.
- By default, `walledclaude` will be able to write to the current directory. Make the docker volume mount `ro` in `walledclaude.sh` if you want strict read-only access. This way Claude can only analyze, not alter.
- Your OAuth token, which lives inside `~/.walledclaude/` is exposed to Claude Code. This is difficult to prevent when using the Pro Plan. When using usage-based billing and the API, the API key can be supplied in an environment variable instead (with just minor adjustments to the script).
- By default, the `.walledclaude` folder in your home directory is mounted and writeable. This means, that Claude Code has access to all your previous conversations and some project data. If you want to isolate this, you can edit the `walledclaude.sh` script to either not mount the claude configuration at all, so that it will start "from scratch" every time or only the stored authentication details.
- The narrow trust boundary means that most prompt injection vectors are unavailable to attackers. However, this also means that some convenience is lost: WebFetch will only work for the whitelisted domains in `squid.conf`. WebSearch can still be used, as it is executed server-side by Anthropic, but it can only retrieve surface-level information from the web. Also, if at any point Anthropic changes its API to execute, e.g., WebFetch on their servers, the proxy becomes useless as exfiltration protection.
- External MCPs will not work unless you whitelist them in `squid.conf`. MCPs hosted on your computer can be connected by binding them to the sandbox bridge gateway instead of `127.0.0.1` (you can see the Zotero MCP example in the comments of `squid.conf` or ask Claude to guide you through it ;)
- Your host uid/gid is passed to the container, so any files it creates are accessible to the current user account
- If Anthropic is compromised, the trust boundary falls apart. However, this would also be the case when running Claude Code in general and cannot be prevented.
- The script cannot guard against zero-day vulnerabilities, which, despite safeguards (docker run options `no-new-privileges` and `drop-caps=ALL`), may allow Claude to break out of the Docker container or otherwise alter your system from within the container

### Things to Improve

- Use rootless docker

## More Details and Specific Measures Taken

All Linux kernel capabilities are dropped to prevent privilege escalation inside the container.
The flags `no-new-privileges` and `cap-drop=ALL` prevent execution of privileged commands even when the user inside the container becomes root.
The first drops the path to becoming root, the second makes sure that, even if it is still somehow possible for the agent to gain root access, root could not do anything.

A light proxy server (`squid`) is spun up via Docker and used to monitor and block any outgoing network calls, except to Anthropics own domains (to keep the model working) and the docker internal network (can be used for local MCP servers).
Once started, the Squid container will persist. However, every time you run `walledclaude`, the Squid configuration is checked for updates and the container is restarted on demand to reflect your changes.

Traffic is limited to HTTPS only.
Keep in mind that this prevents most, but not ALL possible egress vectors due to prompt injection or your own mistakes in prompting: when reading a malicious webpage, your Claude agent could be instructed to exfiltrate data via anthropics own API calls, such as WebSearch or WebFetch somehow.
Although this is very unlikely, it cannot be precluded.
A more real threat is that Anthropic changes the API capabilities, so that an unforeseen egress vector opens.
In any case, the exfiltrated data could include anything inside your current project (the folder you launched this script from, including all subfolders any files therein), the mounted `~/.walledclaude` directory (containing Claude code auth token and past project memories), or `.walledclaude.json`.

To see which external services Claude (tried to) connect to, use the following command: `docker exec claude-egress-proxy tail -f /var/log/squid/access.log`. This allows you to monitor for unexpected behavior and at least detect the scenarios described above.

Instead of `~/.claude.json` and the `~/.claude` directory, this script mounts `~/.walledclaude.json` and `~/.walledclaude`. 
This separates data from your possibly existing `.claude` and `.claude.json` and allows you to revoke the OAuth token separately via the Claude web interface (Settings > Claude Code > Authorization Tokens), if it should ever be compromised.
Also, it obfuscates the paths to the projects you opened with `walledclaude` while still retaining Claude's access to memories from your other previously opened projects.
The folders the memories are stored in reflect the full paths to the project, which for `walledclaude` is always `-workdir-foldername`.
Keep in mind that this may result in name clashes if you open two folders with the same name.

If you want any stricter constraints, it is easy to adapt this script to your needs.
For example, you can start a fresh session every time by just not mounting `~/.walledclaude.json` and `~/.walledclaude`.

## :file_folder: Repository Structure

|              File | Purpose                                                                                                                           |
| ----------------: | :-------------------------------------------------------------------------------------------------------------------------------- |
| `walledclaude.sh` | Shell script containing the `walledclaude` command definition.                                                                    |
|      `squid.conf` | Proxy configuration. Edit this to control the network trust boundary. Some proposals are provided in the comments.                |
|      `Dockerfile` | The definition of the docker container's contents and startup. Edit this to change what software is available inside the sandbox. |
|   `entrypoint.sh` | A helper script for the docker image startup used in the dockerfile.                                                              |
|        `build.sh` | Shell script to build the docker container. Run once in the beginning. Can be used to update the Claude version when run again.   |


## Known issues

- When authenticating upon first launch, one can get stuck in an authentication loop after following the steps in the browser. In this case, open the link provided by Claude Code in a private window.
- The narrow trust boundary essentially makes WebFetch unusable. Claude Code can still obtain *some* information via WebSearch, but no specific site content. You can control the egress trust boundary via `squid.conf` (some suggestions for allow lists are contained in the comments therein).
- The container is kind of large (~2 GiB), as it contains all the usual tools Claude likes to call and you may require for development. You are free to adjust the `Dockerfile` to reduce the size or add additional software (such as a `LaTeX` distribution).
- When opening two folders with the same name, Claude uses the same project directory for memories in `.walledclaude`
- When opening in a git submodule, it can only see the submodule folder and links to the parent `.git` folders are not valid inside the sandbox. Depending on your viewpoint, this is a feature and not a bug.
- Currently not connected to the VS Code Extension, so no in-editor diffs. Can be fixed easily in the future (just need to set `CLAUDE_CONFIG_DIR`, so the extension writes the chosen port to a lock file in the `.walledclaude` directory and allow network traffic to pass through squid). However, this also increases risk, as Claude may edit VS Code configuration, which contains code executed automatically by VS Code.

## :balance_scale: License

I started this project by basing on the excellent scripts/dockerfile provided in [Tim Walls' Blog post](https://snowgoons.ro/posts/2026-05-20-running-claude-code-in-a-docker-container/).
With his permission, this derivative work is released under the MIT License (see [LICENSE](./LICENSE)).



const { getCommitInfo, getPullRequestInfo } = require("@changesets/get-github-info");

const toLinks = (info) => ({
  commit: info?.commit?.markdownLink ?? null,
  pull: info?.pull?.markdownLink ?? null,
  user: info?.author?.markdownLink ?? null,
});

const GITHUB_SERVER_URL = process.env.GITHUB_SERVER_URL || "https://github.com";

function linkifyIssueRefs(line, { repo }) {
  return line.replace(/\[.*?\]\(.*?\)|\B#([1-9]\d*)\b/g, (match, issue) =>
    issue
      ? `[#${issue}](${GITHUB_SERVER_URL}/${repo}/issues/${issue})`
      : match
  );
}

async function getReleaseLine(changeset, _type, options) {
  if (!options?.repo) {
    throw new Error(
      'Please provide a repo to this changelog generator like this:\n"changelog": ["./changelog-config.cjs", { "repo": "org/repo" }]'
    );
  }

  let prFromSummary;
  let commitFromSummary;
  const usersFromSummary = [];

  const replacedChangelog = changeset.summary
    .replace(/^\s*(?:pr|pull|pull\s+request):\s*#?(\d+)/im, (_, pr) => {
      const num = Number(pr);
      if (!isNaN(num)) prFromSummary = num;
      return "";
    })
    .replace(/^\s*commit:\s*([^\s]+)/im, (_, commit) => {
      commitFromSummary = commit;
      return "";
    })
    .replace(/^\s*(?:author|user):\s*@?([^\s]+)/gim, (_, user) => {
      usersFromSummary.push(user);
      return "";
    })
    .trim();

  const [firstLine, ...futureLines] = replacedChangelog
    .split("\n")
    .map((l) => l.trimEnd());

  const links = await (async () => {
    if (prFromSummary !== undefined) {
      let links = toLinks(
        await getPullRequestInfo({ repo: options.repo, pull: prFromSummary })
      );
      if (commitFromSummary) {
        const shortCommitId = commitFromSummary.slice(0, 7);
        links = {
          ...links,
          commit: `[\`${shortCommitId}\`](${GITHUB_SERVER_URL}/${options.repo}/commit/${commitFromSummary})`,
        };
      }
      return links;
    }
    const commitToFetchFrom = commitFromSummary || changeset.commit;
    if (commitToFetchFrom) {
      return toLinks(
        await getCommitInfo({ repo: options.repo, commit: commitToFetchFrom })
      );
    }
    return { commit: null, pull: null, user: null };
  })();

  const users = usersFromSummary.length
    ? usersFromSummary
        .map((u) => `[@${u}](${GITHUB_SERVER_URL}/${u})`)
        .join(", ")
    : links.user;

  const parts = [
    links.commit,
    users ? `by ${users}` : null,
  ].filter(Boolean);

  const prefix = parts.length ? `${parts.join(" ")} -` : "";

  const firstLineLinked = linkifyIssueRefs(firstLine, { repo: options.repo });
  const futureLinked = futureLines
    .map((l) => `  ${linkifyIssueRefs(l, { repo: options.repo })}`)
    .join("\n");

  return `\n\n-${prefix ? ` ${prefix}` : ""} ${firstLineLinked}\n${futureLinked}`;
}

async function getDependencyReleaseLine(changesets, dependenciesUpdated, options) {
  if (!options?.repo) {
    throw new Error(
      'Please provide a repo to this changelog generator like this:\n"changelog": ["./changelog-config.cjs", { "repo": "org/repo" }]'
    );
  }
  if (dependenciesUpdated.length === 0) return "";

  const changesetLink = `- Updated dependencies [${(
    await Promise.all(
      changesets.map(async (cs) => {
        if (cs.commit) {
          const info = await getCommitInfo({
            repo: options.repo,
            commit: cs.commit,
          });
          return toLinks(info).commit;
        }
      })
    )
  )
    .filter(Boolean)
    .join(", ")}]:`;

  const updatedDependenciesList = dependenciesUpdated.map(
    (dep) => `  - ${dep.name}@${dep.newVersion}`
  );

  return [changesetLink, ...updatedDependenciesList].join("\n");
}

module.exports = { getReleaseLine, getDependencyReleaseLine };

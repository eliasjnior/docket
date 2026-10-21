export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "scope-enum": [
      2,
      "always",
      [
        "macos",
        "core",
        "activity",
        "github",
        "persistence",
        "notify",
        "stores",
        "update",
        "cli",
        "ci",
        "deps",
        "release",
        "repo",
        "docs",
      ],
    ],
  },
};

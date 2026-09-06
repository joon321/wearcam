export default [
  { ignores: ["dist/**", "coverage/**"] },
  {
    files: ["**/*.js"],
    languageOptions: {
      parserOptions: { ecmaVersion: "latest", sourceType: "module" },
    },
  },
];

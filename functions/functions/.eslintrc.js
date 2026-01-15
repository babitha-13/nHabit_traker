module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:import/errors",
    "plugin:import/warnings",
    "plugin:import/typescript",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["tsconfig.json", "tsconfig.dev.json"],
    sourceType: "module",
    tsconfigRootDir: __dirname,
  },
  ignorePatterns: [
    "/lib/**/*", // Ignore built files.
    "/generated/**/*", // Ignore generated files.
  ],
  plugins: [
    "@typescript-eslint",
    "import",
  ],
  rules: {
    "quotes": 0,
    "import/no-unresolved": 0,
    "indent": 0,
    "linebreak-style": 0,
    "object-curly-spacing": ["error", "always"],
    "max-len": 0,
    "require-jsdoc": 0,
    "valid-jsdoc": 0,
    "no-trailing-spaces": 0,
    "operator-linebreak": 0,
    "@typescript-eslint/no-unused-vars": ["warn"],
    "comma-dangle": 0,
  },
};

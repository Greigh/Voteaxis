'use strict';
/**
 * Resolves the Google Play service account from either an inline JSON value or
 * a path to the JSON file.
 *
 * The rule here is: if it looks like JSON, it is JSON. Otherwise it is a path.
 * A path is the one credential shape that cannot cross a machine boundary —
 * GOOGLE_PLAY_SA_LOCAL points into the developer's home directory, which a CI
 * runner does not have; GOOGLE_PLAY_SERVICE_ACCOUNT_JSON carries the JSON
 * itself so a GitHub secret can hand it over without a filesystem.
 *
 * @param {NodeJS.ProcessEnv} [env]
 * @param {string} [root] Directory a relative path is resolved against.
 * @returns {{credentials: object, source: string, isPath: boolean}|null}
 * @throws {Error} When a value is present but unusable. The message names the
 *   variable and the reason; it never includes the value, because the value is
 *   a private key.
 */
const fs = require('fs');
const path = require('path');

const INLINE_KEY = 'GOOGLE_PLAY_SERVICE_ACCOUNT_JSON';
const PATH_KEY = 'GOOGLE_PLAY_SA_LOCAL';

function looksLikeJson(value) {
  return value.trimStart().startsWith('{');
}

function parseCredentials(text, source) {
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new Error(
      `${source} is set but is not valid JSON (${e.message}). ` +
      `The private key inside it is not echoed here.`
    );
  }
}

/** The JSON a service account needs, validated well enough to fail early. */
function assertUsable(credentials, source) {
  for (const field of ['client_email', 'private_key']) {
    if (!credentials || !credentials[field]) {
      throw new Error(
        `${source} parsed as JSON but has no "${field}". ` +
        `That is a service-account file, not the credential it should contain.`
      );
    }
  }
  return credentials;
}

/**
 * @returns {null} when neither variable is set — callers treat that as
 *   "not configured" rather than as an error, because a dev box legitimately
 *   has no Play credential.
 */
function resolveServiceAccount(env = process.env, root = process.cwd()) {
  const inline = (env[INLINE_KEY] || '').trim();

  if (inline && looksLikeJson(inline)) {
    return {
      credentials: assertUsable(parseCredentials(inline, INLINE_KEY), INLINE_KEY),
      source: `${INLINE_KEY} (inline)`,
      isPath: false,
    };
  }

  const file = (env[PATH_KEY] || inline).trim();
  if (!file) return null;

  // A value in the *_JSON variable that is neither JSON nor an existing file is
  // the old bug in a new place — say which of the two things it is not.
  const isFromJsonVar = file === inline && !env[PATH_KEY];
  const full = path.resolve(root, file);
  if (!fs.existsSync(full)) {
    throw new Error(
      isFromJsonVar
        ? `${INLINE_KEY} is neither inline JSON (it does not start with "{") ` +
          `nor an existing file. Give it the service-account JSON itself, ` +
          `not a path.`
        : `${PATH_KEY} points at a file that does not exist: ${full}`
    );
  }

  return {
    credentials: assertUsable(
      parseCredentials(fs.readFileSync(full, 'utf8'), PATH_KEY),
      PATH_KEY
    ),
    source: full,
    isPath: true,
  };
}

module.exports = { resolveServiceAccount, INLINE_KEY, PATH_KEY };

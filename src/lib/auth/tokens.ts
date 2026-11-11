import { createHash, randomBytes } from "node:crypto";
export function makeToken() { const token = randomBytes(32).toString("base64url"); return { token, hash: createHash("sha256").update(token).digest("hex") }; }
export function tokenHash(token: string) { return createHash("sha256").update(token).digest("hex"); }

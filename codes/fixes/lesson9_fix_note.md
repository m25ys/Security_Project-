# Lesson 9 Fix

The fix for Lesson 9 (Vulnerable Dependencies) is **identical to the Lesson 1 fix**, because
both lessons share the same root cause: `node-serialize` in `DVSA-ORDER-MANAGER`.

## Apply the fix

```bash
bash fixes/lesson1_apply_fix.sh
```

This script:
1. Downloads the current Lambda deployment package
2. Removes `node-serialize` from `node_modules/`
3. Removes it from `package.json` dependencies
4. Replaces `serialize.unserialize()` with safe `JSON.parse()`
5. Runs `npm audit` to check for remaining issues
6. Repacks and redeploys the Lambda

## Verify

```bash
bash lesson9/verify_fix.sh
```

## Additional hardening (Lesson 9 specific)

To prevent future vulnerable dependencies from being introduced:

1. Add `npm audit` to your CI/CD pipeline
2. Pin dependency versions in `package.json` using exact versions (no `^` or `~`)
3. Use `npm ci` instead of `npm install` in production builds
4. Regularly run `npm audit fix` and review changelogs before upgrading

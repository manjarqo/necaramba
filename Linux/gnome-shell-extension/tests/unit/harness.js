// Minimal dependency-free test harness for `gjs -m`.
const tests = [];
export function test(name, body) { tests.push({name, body}); }
export function assertEqual(actual, expected, message = '') {
    const a = JSON.stringify(actual), e = JSON.stringify(expected);
    if (a !== e) throw new Error(`${message} expected ${e}, got ${a}`);
}
export function run() {
    let failed = 0;
    for (const {name, body} of tests) {
        try { body(); print(`ok   ${name}`); }
        catch (error) { failed++; print(`FAIL ${name}\n     ${error.message}`); }
    }
    print(`\n${tests.length - failed} passed, ${failed} failed`);
    return failed;
}

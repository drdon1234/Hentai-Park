// Verifies Pica request signing without an account: a bogus sign-in must be rejected as
// "invalid email or password" (signature errors come back as a different code).
import { loadSource } from './host.mjs';
const { def } = await loadSource('pica.js');
const { status, json } = await def.send('POST', 'auth/sign-in', { email: 'park-test-nobody', password: 'x' });
console.log(status, JSON.stringify(json));

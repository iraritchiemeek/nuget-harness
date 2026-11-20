// k6 load script for the spec 02b benchmark (scripts/runner/benchmark.ps1 runs it).
// Sends the request mix in MIX (a JSON array of paths, written by benchmark.ps1) to BASE_URL: with
// VUS concurrent virtual users for DURATION, or, when ITERATIONS is above 0, ITERATIONS requests by
// one user. The n-th request of the whole test is MIX[n mod length], so every app gets the same
// sequence. Writes the summary to SUMMARY as JSON.
import http from 'k6/http';
import exec from 'k6/execution';

const mix = JSON.parse(open(__ENV.MIX));
const baseUrl = __ENV.BASE_URL;
const iterations = Number(__ENV.ITERATIONS);

export const options = {
  scenarios: {
    load:
      iterations > 0
        ? { executor: 'shared-iterations', vus: 1, iterations, maxDuration: '10m' }
        : { executor: 'constant-vus', vus: Number(__ENV.VUS), duration: __ENV.DURATION },
  },
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
  // Both apps serve HTTPS on localhost with self-signed certificates.
  insecureSkipTLSVerify: true,
  // Every recorded request in the mix answers 200; anything else counts in http_req_failed.
  discardResponseBodies: true,
  // Not limits: a threshold on a tagged metric makes k6 count it in the summary, and benchmark.ps1
  // checks that both apps were called with the same HTTP and TLS versions.
  thresholds: {
    'http_reqs{proto:HTTP/1.1}': ['count>=0'],
    'http_reqs{proto:HTTP/2.0}': ['count>=0'],
    'http_reqs{tls_version:tls1.2}': ['count>=0'],
    'http_reqs{tls_version:tls1.3}': ['count>=0'],
  },
};

export default function () {
  http.get(baseUrl + mix[exec.scenario.iterationInTest % mix.length]);
}

export function handleSummary(data) {
  return { [__ENV.SUMMARY]: JSON.stringify(data, null, 2) };
}

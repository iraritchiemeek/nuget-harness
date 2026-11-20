// k6 load script for the spec 02b benchmark (scripts/runner/benchmark.ps1 runs it).
// Sends the request mix in MIX (a JSON array of paths, written by benchmark.ps1) to BASE_URL, with
// VUS concurrent virtual users for DURATION. The n-th request of the whole test is MIX[n mod length],
// so every app gets the same sequence. Writes the summary to SUMMARY as JSON.
import http from 'k6/http';
import exec from 'k6/execution';

const mix = JSON.parse(open(__ENV.MIX));
const baseUrl = __ENV.BASE_URL;

export const options = {
  scenarios: {
    load: { executor: 'constant-vus', vus: Number(__ENV.VUS), duration: __ENV.DURATION },
  },
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
  // The old app is served over HTTPS with a self-signed certificate (IIS Express).
  insecureSkipTLSVerify: true,
  // Every recorded request in the mix answers 200; anything else counts in http_req_failed.
  discardResponseBodies: true,
};

export default function () {
  http.get(baseUrl + mix[exec.scenario.iterationInTest % mix.length]);
}

export function handleSummary(data) {
  return { [__ENV.SUMMARY]: JSON.stringify(data, null, 2) };
}

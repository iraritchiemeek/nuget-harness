# Draft comment for issue #5675 (not posted)

Everything below the line is the text to post.

Not to be posted before the repository owner approves it, after the independent review. The backing of each claim is in [`evidence/03/run-log.md`](../evidence/03/run-log.md).

---

I'd like to fix this. It still happens on `dev` at 06b7a81: on a gallery running in CI, with an ownership request for an ID that has no versions, the manage packages page returned a 500 for both the sender and the receiver of the request ([run](https://github.com/iraritchiemeek/nuget-harness/actions/runs/44977407429)). The change keeps the request in the list, so the receiver can accept or reject it. The sender can't cancel it from the page. Leaving such requests out of the list would also work, if you'd rather have that. The bug was found by reading the open issues. AI agents wrote the fix and its tests, and a human approved posting this. Is a pull request welcome?

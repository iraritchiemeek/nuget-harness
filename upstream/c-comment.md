# Draft comment for issue #5675 (not posted)

Everything below the line is the text to post.

---

I'd like to fix this. It still happens on `dev`: with an ownership request for an ID that has no versions, the manage packages page returned a 500 on a local gallery, for both the sender and the receiver of the request. The change keeps the request in the list, so the receiver can still accept or reject it. Leaving such requests out of the list would also work, if you'd rather have that. AI agents wrote the fix and its tests, and a human approved posting this. Is a pull request welcome?

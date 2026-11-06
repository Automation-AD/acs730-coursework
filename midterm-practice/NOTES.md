# Midterm Practice -- Notes

## Task 5: git hygiene

Deleting the `.tfstate` file and the hard-coded keys in a new commit only removes them from the latest snapshot: every earlier commit still contains them, and anyone who cloned or forked this public repository already has that history, so a real leaked credential must be revoked and rotated (and the history rewritten with `git filter-repo` if needed), not just deleted.

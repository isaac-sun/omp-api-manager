# Configuration safety

Every future configuration write follows this transaction:

1. Read the target file and calculate a fingerprint (SHA-256, byte count, modification time).
2. Parse YAML into a semantic value tree.
3. Apply a targeted mapping update only after the OMP version adapter accepts the schema.
4. Check the fingerprint again immediately before mutation.
5. Copy a timestamped backup beside the original file.
6. Serialize to a sibling temporary file and parse that temporary content again.
7. Recheck the source fingerprint immediately before atomic replacement, then re-read for confirmation.

If an external edit changes the fingerprint, the operation fails with a conflict instead of overwriting data. If parsing, backup, or replacement fails, the original is untouched. Backup restore validates YAML and uses the same transaction, first backing up the current configuration. Backups are listed newest-first and automatic retention never reduces the set below ten files.

Yams preserves the meaning of unknown fields carried in the decoded value tree. It cannot preserve comments and formatting exactly; users are warned of this limitation and can compare/restore the generated backup. The app never edits YAML with string replacement or regular expressions.

The advanced `models.yml` editor returns only a sanitized serialization to the UI. Fields whose names indicate a secret (`apiKey`, `authorization`, `token`, `secret`, or `password`) are represented by a redaction marker. On save, an unchanged marker restores the on-disk value in memory; a user cannot replace it with plaintext. This also permits a legacy plaintext secret already present in a user's file to remain unchanged while another field is edited, without exposing it in the UI. New secret references must begin with `!` and should point to Keychain-backed commands; migrate legacy values by saving the Provider through the app.

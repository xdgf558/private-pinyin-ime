# Windows TSF Notes

Stage 4 will implement the Windows Text Services Framework host.

## Target

- Windows 11.
- C++ 20.
- TSF in-process text service DLL.
- Calls the shared Rust core through the C ABI.

## Required References

- Microsoft Text Services Framework and IME requirements.
- Microsoft Text Services Framework overview.

## Constraints

- Do not directly set the system default input method through registry writes.
- Do not access the network by default.
- Candidate windows must not take focus.

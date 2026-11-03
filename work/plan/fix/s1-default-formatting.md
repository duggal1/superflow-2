# S1-mini default formatting
Root cause: persisted cleanup settings default to prose, restricting the model's list formatting.
- Default to semi-formal, lists, general; migrate older saved prose defaults once while preserving later user choices and CPU selections.
- Keep the documented prompt, greedy decoding, token cap, safety gate, and explicit formatting controls.
- Verify settings migration and list/prose behavior with focused tests and a real S1-mini inference.

1. Reduce stop-to-insertion latency for long dictations, including a long replay that represents a 30-minute session.
2. Keep cleanup transcript-safe: preserve words, order, technical terms and final ASR corrections, with raw fallback whenever cleanup is incomplete.
3. Use parallel S1-mini work only where measured throughput and machine memory show it helps; avoid exhausting the 8 GB Mac and scarce SSD.
4. Prove performance with real app pipeline replay, completed output checks, repeated measurements, fallback/error counts, and resource measurements in milliseconds.
5. Keep existing unrelated background workloads running and do not spawn subagents.
6. Commit and push the completed change to main.

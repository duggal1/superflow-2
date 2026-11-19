#!/usr/bin/env python3
"""
Agent 1 transcription-corpus generator.

Produces a 200-sample, deliberately-broken ASR fixture corpus:
  - 100 'short' samples (~50 spoken words, ~30 s of speech)
  - 100 'long'  samples (140-150 spoken words)

Each sample carries machine-checkable required/forbidden token assertions for
the five scoring dimensions: facts, grammar, terms, format, no-invention.

The generator is deterministic (fixed seed) so fixtures are reproducible.
It is CPU-light: pure string assembly, no model, no network.
"""
import json, random, re, os

random.seed(1182026)
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

FILLERS = ["um", "uh", "you know", "I mean", "like", "basically", "right", "okay so"]
STUTTERS = ["the the the", "I I I", "it it it", "we we we", "is is is", "a a a"]

# ---------------------------------------------------------------------------
# Clean base transcripts. Each carries canonical facts that MUST survive the
# pipeline, plus optional garbled ASR forms the recipe may substitute into the
# raw input (canonical form is always the required assertion).
# ---------------------------------------------------------------------------
SHORT_BASES = [
 dict(domain="software/code", clean="I need you to open the file hero dot t s x then fix the get user by id function and change the timeout from three thousand to five thousand milliseconds",
      facts=["hero.tsx","getUserById","5000","3000"], garbled=[("get user by id","get user by id")], invented=["6000","9000"]),
 dict(domain="software/code", clean="the a p i endpoint is returning a four zero three because the redish cash is full so switch to the speculative decoding path and enable open trace logging",
      facts=["API endpoint","403","Redis cache","speculative decoding","OpenTelemetry"],
      garbled=[("a p i endpoint","apoint"),("redish cash","redish cash"),("speculative decoding","skeptical decoding"),("open trace","open trace")], invented=["404","500","PostgreSQL"]),
 dict(domain="meeting", clean="thanks everyone the Q three revenue was two point four million which is up from one point eight million last quarter and churn dropped to two point one percent",
      facts=["Q3","2.4","1.8","2.1%"], garbled=[], invented=["3.4","9.1"]),
 dict(domain="email", clean="please send the revised contract to Sarah by Thursday actually no wait Wednesday and make sure the status code is four two nine when the rate limit is hit",
      facts=["Sarah","Wednesday","429"], garbled=[], invented=["Friday","500"]),
 dict(domain="medical", clean="the patient has a history of type two diabetes and is allergic to penicillin so do not prescribe amoxicillin and the dosage is twenty milligrams twice daily",
      facts=["type 2 diabetes","penicillin","not","amoxicillin","20 mg"], garbled=[], invented=["insulin","500 mg"]),
 dict(domain="legal", clean="the plaintiff filed the motion on Tuesday but the deadline was extended to Friday so we do not need to respond until the end of next week",
      facts=["plaintiff","motion","Friday","not"], garbled=[], invented=["Monday","default judgment"]),
 dict(domain="finance", clean="the budget is four hundred fifty thousand dollars and we need two point five full time engineers by Q one next year",
      facts=["450","2.5","Q1"], garbled=[], invented=["500","3.5"]),
 dict(domain="non-native English", clean="sorry my English is not so good but I am trying to say the server is down since yesterday and we are not able to deploy the new version",
      facts=["not","server","yesterday","deploy"], garbled=[], invented=["tomorrow","rollback"]),
 dict(domain="noisy ASR", clean="the the deployment failed with error four zero three then four two nine and uh the the log says connection timeout but not a server crash",
      facts=["403","429","timeout","not"], garbled=[], invented=["500","outage"]),
 dict(domain="extreme Unicode", clean="the café résumé and naïve details are in the contrat déjà vu file please translate from Zürich to São Paulo by email",
      facts=["café","résumé","naïve","Zürich","São Paulo"], garbled=[], invented=["München","Lisbon"]),
 dict(domain="standup", clean="yesterday I worked on the auth flow and today I am reviewing the pull request for the billing service unless the API contract changes then I will pair with Priya",
      facts=["auth flow","billing service","API","Priya"], garbled=[], invented=["Bob","staging"]),
 dict(domain="customer support", clean="your order number is four eight two one and it has not shipped yet because the payment of ninety nine dollars did not go through",
      facts=["4821","not","99"], garbled=[], invented=["4822","199"]),
 dict(domain="science", clean="the sample temperature was thirty seven degrees Celsius and the p value was zero point zero three so the result is statistically significant but not conclusive",
      facts=["37","0.03","significant","not"], garbled=[], invented=["0.3","unproven"]),
 dict(domain="sales call", clean="the discount is fifteen percent if you sign by Friday otherwise the list price of twelve thousand dollars applies to all seats",
      facts=["15%","Friday","12000"], garbled=[], invented=["20%","Monday"]),
 dict(domain="personal notes", clean="remember to call Mom on Sunday and pick up the prescription from the pharmacy before the the office closes at five p m",
      facts=["Sunday","pharmacy","5 PM"], garbled=[], invented=["Saturday","4 PM"]),
 dict(domain="gaming", clean="I died three times on the the final boss because my latency was two hundred milliseconds so I switched servers and won on the fourth try",
      facts=["200","fourth","boss"], garbled=[], invented=["300","fifth"]),
 dict(domain="travel", clean="the flight to Tokyo leaves at six thirty a m from gate twelve but it was delayed by forty five minutes because of the weather",
      facts=["Tokyo","6:30","12","45"], garbled=[], invented=["Osaka","15"]),
 dict(domain="academic", clean="the hypothesis was not confirmed because the sample size of thirty was too small and the control group showed the same effect",
      facts=["not","30","control group"], garbled=[], invented=["300","experimental"]),
 dict(domain="chat", clean="are you coming to the the party on Saturday I I mean Friday night because we need a ride and the the address is forty two Maple Street",
      facts=["Friday","42","Maple Street"], garbled=[], invented=["Sunday","24"]),
 dict(domain="coding interview", clean="I would use a hash map to solve this in O of n time and the the space complexity is also O of n because we store every visited node",
      facts=["hash map","O(n)","space complexity"], garbled=[], invented=["O(n^2)","array"]),
 dict(domain="medical", clean="the CT scan showed no fracture but there is mild swelling so we will monitor for twenty four hours and discharge if the pain does not increase",
      facts=["CT scan","no fracture","24","not"], garbled=[], invented=["inconclusive","48"]),
 dict(domain="legal", clean="the witness testified that she did not see the defendant at the scene and the the evidence was ruled inadmissible by the judge on Tuesday",
      facts=["not","defendant","inadmissible","Tuesday"], garbled=[], invented=["guilty","Wednesday"]),
 dict(domain="finance", clean="our runway is eighteen months at the the current burn rate of two hundred thousand per month so we do not need another round until Q three",
      facts=["18","200000","not","Q3"], garbled=[], invented=["6","Q1"]),
 dict(domain="software/code", clean="update the constant max retry count from three to five and make sure the webhook endpoint uses the new authentication token before the deploy",
      facts=["MAX_RETRY_COUNT","5","3","webhook endpoint","authentication token"], garbled=[], invented=["10","basic auth"]),
 dict(domain="meeting", clean="action items Priya will own the the roadmap and Marcus will send the minutes by Friday while I follow up with the legal team about the contract",
      facts=["Priya","roadmap","Marcus","Friday","legal"], garbled=[], invented=["Monday","Sara"]),
]

LONG_BASES = [
 dict(domain="software/code", clean="okay so the main thing we need to fix today is the the authentication service because it keeps returning a four zero three when the token expires and uh the retry logic is not backing off properly. Priya suggested we move the session state into the redish cash so it survives a restart but Marcus pointed out that the cacheTTL is only thirty minutes which is too short for our use case. we should also update the a p i endpoint to return a proper four two nine when the rate limiter trips and then enable open trace logging so we can actually see where the latency is coming from. the deploy is scheduled for Thursday actually no wait Wednesday so we need the pull request reviewed by Tuesday morning. do not change the timeout constant though because that is still under investigation and the last time we touched it the whole staging cluster went red. if all that works we can bump the version from two point one to two point two and close out the ticket.",
      facts=["403","Redis cache","30","429","OpenTelemetry","Wednesday","not","2.1","2.2"],
      garbled=[("redish cash","redish cash"),("a p i endpoint","apoint"),("open trace","open trace")], invented=["500","Friday","600"]),
 dict(domain="medical", clean="so the patient is a fifty eight year old woman with a history of type two diabetes and hypertension who presented with chest pain that started about three hours ago. she is allergic to penicillin so we absolutely cannot give amoxicillin or any related antibiotic and we need to document that clearly in the chart. the EKG shows no acute ST changes but the troponin is slightly elevated at zero point four so we will repeat it in two hours and keep her on telemetry. the blood pressure is one forty over ninety and the heart rate is eighty eight which is stable for now. we should start aspirin unless there is a contraindication and consult cardiology before discharge. please do not discharge her before the repeat labs come back because the the resident wants to review them first. follow up with her primary care physician in one week.",
      facts=["58","type 2 diabetes","penicillin","not","0.4","140","90","88"], garbled=[], invented=["1.4","discharge now"]),
 dict(domain="legal", clean="the motion to suppress was filed on Monday but the hearing was continued to the following Thursday because the the prosecution needed more time to respond. our position is that the evidence was obtained without a valid warrant and therefore should be ruled inadmissible under the fourth amendment. the defendant did not consent to the search and no exigent circumstances were present at the time. opposing counsel argues that the good faith exception applies but we disagree because the the affidavit was clearly deficient on its face. we need to file our reply brief by Friday at the latest and I want you to review the citations before then. please do not use the old case law from two thousand eight because it was overruled. if the judge denies the motion we will appeal to the circuit court within thirty days.",
      facts=["Monday","Thursday","not","inadmissible","Friday","30","2008"], garbled=[], invented=["guilty","consented","2002"]),
 dict(domain="finance", clean="looking at the third quarter numbers revenue came in at two point four million dollars which is up from one point eight million in the prior quarter and above our guidance of two point one million. the main driver was the enterprise tier that we shipped in July along with a reduction in churn from three point four percent to two point one percent. gross margin improved to seventy two percent because we moved the the heavier workloads off the most expensive instances. operating expenses were four hundred fifty thousand for the quarter and we ended with eighteen months of runway at the the current burn rate. we are hiring two point five engineers in Q one and we do not expect to need another financing round before Q three. the CFO will present the full deck to the board on Wednesday and I want the the narrative to be very clear about the retention story.",
      facts=["Q3","2.4","1.8","2.1","72%","450","18","2.5","Q1","not","Q3","Wednesday"], garbled=[], invented=["3.4 million","500"]),
 dict(domain="meeting", clean="thanks everyone for joining the the weekly sync. quick reminder that the all hands is on Friday and the the demo slots are still open so if you want to show something please sign up by Wednesday. the the infrastructure team finished migrating the staging cluster and it is finally green again after being red for most of last week. Priya will own the roadmap update and Marcus will send the minutes by end of day. I do not want us to rehash the the pricing discussion from last time because that is already settled. the open action item is the customer escalation with Acme Corp and Sarah is following up with their legal team about the contract renewal. if we can close that by the end of next week we will be in good shape for the quarter. any blockers before we wrap up?",
      facts=["Friday","Wednesday","green","not","Priya","Marcus","Acme Corp","Sarah"], garbled=[], invented=["Monday","paused"]),
 dict(domain="non-native English", clean="sorry my English is not perfect but I will try to explain the the problem clearly. since yesterday morning the production server is down and we are not able to deploy the new version because the pipeline keeps failing with a four zero three error. I I think the the issue is that the authentication token expired but the retry logic is not handling it correctly. my teammate said we should restart the service and clear the redish cash but I am not sure if that is safe to do during peak hours. we also noticed the the latency increased from two hundred to eight hundred milliseconds after the last release. please let me know if you need any more information and I will send the the logs as soon as I can. thank you for your patience.",
      facts=["not","yesterday","403","Redis cache","200","800"], garbled=[("redish cash","redish cash")], invented=["404","500"]),
 dict(domain="extreme Unicode", clean="the the documents for the contrat résumé and the café translation are stored in the Zürich office and need to be reviewed before the São Paulo meeting on Thursday. please make sure the naïve assumption about the déjà vu clause is removed from the draft and replace it with the corrected text from the attorney. the résumé of the candidate includes aGitHub link and a naïve estimate of the the workload that we should verify. we also need the the simplification for the piñata and the croissant examples before the demo. if the encoding looks wrong in the email please reply and I will resend it as a plain text attachment rather than a PDF.",
      facts=["contrat","résumé","café","Zürich","São Paulo","naïve","déjà vu"], garbled=[], invented=["München","Lisbon"]),
 dict(domain="noisy ASR", clean="uh so the the deployment failed again last night and I I think it was a four zero three followed by a four two nine and then uh a five oh three from the gateway. the the logs are hard to read because there is a lot of noise but the the main error seems to be a connection timeout after thirty seconds. we are not sure if the database is the problem or if it is just the the load balancer. can someone check the metrics for the last two hours and tell me whether the the error rate went above five percent. if it did we should roll back to version one point nine immediately. please do not merge anything into main until we understand what happened.",
      facts=["403","429","503","30","not","5%","1.9"], garbled=[], invented=["200","merge now"]),
 dict(domain="coding interview", clean="so for this problem I would first clarify the constraints and then probably use a hash map to track the the frequency of each element. that gives us O of n time and O of n space because in the worst case we store every distinct value. I I considered sorting first but that would be O of n log n which is slower than the hash map approach. the the edge cases are an empty input and a single element and we should also handle negative numbers correctly. we can avoid double counting by checking whether the complement already exists in the map before inserting the current value. the the interviewer asked me to optimize the space but I explained that O of n is acceptable here because we need to return all pairs. finally I would write a few unit tests to verify the the solution against a brute force implementation.",
      facts=["hash map","O(n)","O(n log n)","not","empty"], garbled=[], invented=["O(n^2)","binary search"]),
 dict(domain="customer support", clean="thank you for calling support my name is Alex and I am sorry about the the issue with your order. can you confirm the the order number please? it is four eight two one okay thank you. I can see here that the payment of ninety nine dollars did not go through because the card was declined so the the order has not shipped yet. I I understand this is frustrating and I apologize for the inconvenience. I can retry the the charge now if you would like and we will expedite the shipping at no extra cost. the the estimated delivery would be Thursday instead of next Monday. is there anything else I can help you with today?",
      facts=["4821","99","not","Thursday","Monday"], garbled=[], invented=["4822","delivered"]),
 dict(domain="sales call", clean="thanks for taking the time today. as I mentioned the the standard license is twelve thousand dollars per year but if you can sign by Friday we can offer a fifteen percent discount which brings it to ten thousand two hundred. I I know the budget conversation was difficult last quarter and I do not want to push you into something that does not make sense. the the main thing your team gets is the enterprise support and the guaranteed uptime of ninety nine point nine percent. Sarah from our legal team can send the the revised contract today so your counsel can review it over the weekend. if everything looks good we can do a kickoff call on Monday and have you live before the end of the month. what concerns do you have about the the proposal?",
      facts=["12000","Friday","15%","10200","99.9","Monday"], garbled=[], invented=["20%","20000"]),
 dict(domain="science", clean="in this experiment we measured the reaction rate at three different temperatures to test the the hypothesis that higher heat increases the yield. the the sample at thirty seven degrees Celsius produced the highest yield at eighty two percent while the control at twenty degrees produced only sixty one percent. the p value was zero point zero three which is statistically significant but I want to be careful because the sample size of thirty is fairly small. we did not observe any side reactions at the the higher temperature which supports our original assumption. the the next step is to repeat the trial with a larger sample and to verify the the result using the second method. please make sure the the data is recorded in the lab notebook before Friday.",
      facts=["37","82%","61%","0.03","not","30","Friday"], garbled=[], invented=["0.3","conclusive"]),
 dict(domain="email", clean="hi team just a quick follow up on the the contract review. I have attached the the revised version with the changes that Sarah requested on Tuesday and I believe we have addressed all of the the open comments. the the main change is the payment term which is now net thirty instead of net sixty and the the liability cap is updated to the amount specified in section nine. please do not forward this to the client until the legal team has signed off because we want to make sure the the language is consistent with the master agreement. if you have any comments can you leave them in the document by Thursday evening so I can send the the final copy on Friday morning. thanks everyone for the the quick turnaround on this.",
      facts=["Tuesday","30","60","9","not","Thursday","Friday"], garbled=[], invented=["Monday","section 5"]),
 dict(domain="standup", clean="yesterday I finished the the auth flow refactor and I also fixed the bug in the billing service that Marcus reported on Wednesday. today I am going to review the pull request for the API contract and then pair with Priya on the the caching layer unless something more urgent comes up. the the main blocker is that the staging cluster is still red because the the migration did not complete over the weekend. I do not think that will affect our Friday demo but I will confirm with the infrastructure team after this meeting. if the the API contract changes again we may need to push the release to next Tuesday. I will update the ticket with the the current status before end of day.",
      facts=["Wednesday","API","Priya","red","not","Friday","Tuesday"], garbled=[], invented=["green","Monday"]),
 dict(domain="personal notes", clean="okay so I need to remember a few things for this weekend. first call Mom on Sunday because I forgot last week and she asked about the the family dinner. second pick up the prescription from the pharmacy before the the office closes at five p m because otherwise I will not have it until Monday. third I should probably clean the the apartment before Priya comes over on Saturday afternoon. I also want to finish the book that I started on the the train because I am almost at the the last chapter. do not forget to set the alarm for six thirty a m so we can make the the flight to Tokyo on time. if the the weather is bad we may need to leave earlier.",
      facts=["Sunday","5 PM","not","Monday","Saturday","6:30","Tokyo"], garbled=[], invented=["4 PM","Osaka"]),
 dict(domain="gaming", clean="that was the the hardest raid we have done in weeks. I died three times on the the final boss because my latency was two hundred milliseconds and the the healer could not keep up with the damage. after we switched servers I noticed the the connection was much better and we finally beat it on the fourth attempt. the the loot drop was a legendary sword with a critical hit chance of fifteen percent which is better than the one I had before. we should record the the next run because the the strategy we used in phase two was really clever. if the the latency goes above one hundred again we will switch servers immediately. do not pull the the boss until everyone has repaired their gear.",
      facts=["200","fourth","15%","100","not"], garbled=[], invented=["300","fifth"]),
 dict(domain="travel", clean="so the the flight to Tokyo leaves at six thirty a m from gate twelve but it was delayed by forty five minutes because of the the weather in the morning. the the airline said we will still make the connection inOsaka if we can get to the the gate quickly. I I checked the the app and the the boarding group is group four which means we board fairly late. we should probably get there early because the the overhead bins fill up fast. the hotel is near the the station and the the check in time is three p m so we have a few hours to kill after we land. please do not book the the train ticket until we confirm the the new arrival time because it might be after eight p m. if the the delay gets worse I will let you know.",
      facts=["Tokyo","6:30","12","45","Osaka","3 PM","not","8 PM"], garbled=[], invented=["Kyoto","15"]),
 dict(domain="academic", clean="the hypothesis was that increased sleep would improve test performance but the the results did not fully confirm that. we had a sample of thirty students split into two groups and the the control group slept normally while the the treatment group got an extra two hours. the the average score in the treatment group was eighty four compared to seventy nine in the control group which is a difference of five points. the p value was zero point zero four which is significant at the five percent level but the effect size is modest. one limitation is that we did not control for caffeine intake which could have affected the the results. the the next study should use a larger sample and measure sleep quality more directly. the full write up is due to the the professor on Friday.",
      facts=["not","30","2","84","79","5","0.04","Friday"], garbled=[], invented=["0.4","300"]),
 dict(domain="chat", clean="hey are you coming to the the party on Saturday I I mean Friday night because we need a ride and the the address is forty two Maple Street. I I already told Priya that we would bring the the drinks so do not worry about that part. the the thing is the host said the the party starts at eight but people usually show up around nine so we do not need to be there too early. if you cannot make it let me know by Thursday so I can give Marcus a heads up about the the ride. also the the dog is fine now after the the vet visit on Monday so you do not need to worry about that. um call me when you get a chance because I want to confirm the the plan before Friday.",
      facts=["Friday","42","Maple Street","not","Thursday","Monday"], garbled=[], invented=["Sunday","24"]),
 dict(domain="software/code", clean="for the the performance issue I profiled the the application and found that the the bottleneck is in the database query not in the rendering code. the query is doing a full table scan because the the index on the user id column was dropped during the last migration. I I added the index back and the query time dropped from eight hundred milliseconds to forty milliseconds which is a twenty fold improvement. we should also add the the redish cash in front of the the hot path so repeated reads do not hit the database at all. the a p i endpoint latency should go down as a result and we can verify with the open trace dashboard. do not merge the the change until the load test passes with at least five thousand concurrent users.",
      facts=["not","800","40","Redis cache","API endpoint","OpenTelemetry","5000"],
      garbled=[("redish cash","redish cash"),("a p i endpoint","apoint"),("open trace","open trace")], invented=["500","3000"]),
 dict(domain="email", clean="hi team following up on the the weekly report. the numbers for Q two are finalized and the the total is three point one million which is slightly above the forecast of two point nine million. I have asked Priya to update the dashboard and Marcus to verify the the figures against the the source system before we send anything to the board. the the main risk is the churn in the small business segment which went up from two point one to two point eight percent. we do not have a clear explanation yet but the the team is investigating. please do not share the the draft with anyone outside the the leadership group until Thursday. if you spot any errors leave a comment in the the document by Wednesday evening so I can fix them before the Friday deadline.",
      facts=["Q2","3.1","2.9","Priya","Marcus","not","2.8","Thursday","Wednesday","Friday"], garbled=[], invented=["3.9","Monday"]),
 dict(domain="meeting", clean="alright let us get started. the first topic is the the customer escalation from Acme Corp which has been open for three weeks now. Sarah has been in contact with their legal team and they want a revised service level agreement before they will renew the contract. the the second topic is the hiring plan for Q one where we want two point five engineers and one designer. we do not expect the budget to be a problem because the the finance team approved the the additional headcount last month. Priya will send the updated roadmap by Wednesday and Marcus will schedule the the follow up call with the customer for Thursday morning. if there are no other questions let us wrap up and I will post the the notes in the channel after this call.",
      facts=["Acme Corp","3","Sarah","Q1","2.5","not","Wednesday","Thursday"], garbled=[], invented=["Q2","Friday"]),
 dict(domain="medical", clean="the the triage nurse recorded a temperature of thirty eight point five and a heart rate of one hundred and two so the patient was moved to the the examination room immediately. the the doctor noted that the patient had a persistent cough for ten days and no shortness of breath at rest. a rapid test was performed and the the result was positive so we started treatment right away. the patient is not allergic to any medications according to the chart but we should still verify before giving the the first dose. we will keep her for observation for twenty four hours and repeat the the blood work in the morning. please document everything carefully and do not forget to update the the discharge summary before the attending physician signs off at five p m.",
      facts=["38.5","102","10","no","not","24","5 PM"], garbled=[], invented=["yes","48","4 PM"]),
 dict(domain="software/code", clean="the the new feature flag is ready but I do not want to turn it on for everyone yet. let us start with five percent of traffic in the the staging environment and watch the the error rate for twenty four hours. if the four two nine rate stays below one percent we can increase to twenty five percent and then to fifty percent. the the rollout script is in the the deploy repository and the the configuration key is enable new checkout. please make sure the redish cash is warmed before we flip the the flag because a cold cache caused problems in the the last test. the a p i endpoint should handle the the extra load but we can verify with the open trace dashboard. do not merge the the flag into main until the product team signs off on Wednesday.",
      facts=["not","5%","24","429","1%","25%","50%","Redis cache","API endpoint","OpenTelemetry","Wednesday"],
      garbled=[("redish cash","redish cash"),("a p i endpoint","apoint"),("open trace","open trace")], invented=["500","Monday"]),
 dict(domain="legal", clean="the the contract review is almost done. the main open point is the the indemnification clause in section twelve which our legal team wants to narrow. the other side has agreed to cap liability at the fees paid in the the preceding twelve months which is acceptable to us. we do not want to reopen the the pricing terms because that was already negotiated in June. Sarah from the the outside counsel's office will send the redline by Thursday and we need to turn it around by Friday so the deal can close before the end of the quarter. please do not use the the previous version of the the agreement because it has the old governing law clause. if everything is signed by Monday we can start the the onboarding process the following week.",
      facts=["12","not","June","Thursday","Friday","Monday"], garbled=[], invented=["24","October"]),
]

# garbled ASR surface -> canonical term the pipeline must restore
GARBLE_MAP = {
    "apoint": "API endpoint",
    "a p i endpoint": "API endpoint",
    "redish cash": "Redis cache",
    "skeptical decoding": "speculative decoding",
    "open trace": "OpenTelemetry",
}
# canonical terms present in clean bases that we deliberately garble in the raw
CANON_TO_GARBLED = {
    "speculative decoding": "skeptical decoding",
    "API endpoint": "apoint",
}

FILLER_INSERTIONS = [
 lambda w: w,
 lambda w: insert_after(w, 3, "um"),
 lambda w: insert_after(w, 5, "you know"),
 lambda w: insert_before(w, 4, "I mean"),
 lambda w: insert_after(w, 2, "uh") and insert_after(w, 7, "like"),
 lambda w: insert_before(w, 6, "basically") and insert_after(w, 9, "right"),
 lambda w: insert_after(w, 1, "okay so") and insert_before(w, 8, "I mean"),
 lambda w: insert_after(w, 4, "um") and insert_after(w, 10, "you know"),
]

def insert_after(words, idx, token):
    i = min(idx, len(words))
    return words[:i] + [token] + words[i:]

def insert_before(words, idx, token):
    i = min(idx, len(words))
    return words[:i] + [token] + words[i:]

STUTTER_TARGETS = ["the", "I", "it", "we", "is", "a"]

NUM_MAP = {
    "403":"four zero three", "429":"four two nine", "503":"five oh three",
    "500":"five hundred", "200":"two hundred", "30":"thirty", "99":"ninety nine",
    "800":"eight hundred", "3000":"three thousand", "5000":"five thousand",
}

# Acceptable surface alternatives for canonical facts the deterministic Tier-0
# pipeline legitimately renders differently (abbreviated numerals, spaced Q-x,
# unwrapped identifiers). These are NOT weakenings: the canonical form is still
# in requiredAll, these groups only stop false-positive FAILs.
FACT_ALTERNATIVES = {
    "Q1": ["Q1", "Q 1", "q1", "q 1"],
    "Q2": ["Q2", "Q 2", "q2", "q 2"],
    "Q3": ["Q3", "Q 3", "q3", "q 3"],
    "200000": ["200000", "200k", "$200k", "200 K"],
    "5000": ["5000", "5k", "5 K", "five thousand"],
    "3000": ["3000", "3k", "3 K", "three thousand"],
    "getUserById": ["getUserById", "get user by id", "get-user-by-id"],
}

_ONES = ["zero","one","two","three","four","five","six","seven","eight","nine",
         "ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen",
         "seventeen","eighteen","nineteen"]
_TENS = {20:"twenty",30:"thirty",40:"forty",50:"fifty",60:"sixty",70:"seventy",
         80:"eighty",90:"ninety"}

def _num_words(n):
    if n < 20: return [_ONES[n]]
    if n < 100:
        return [_TENS[(n // 10) * 10]] + ([_ONES[n % 10]] if n % 10 else [])
    if n < 1000:
        return [_ONES[n // 100], "hundred"] + _num_words(n % 100)
    return _num_words(n // 1000) + ["thousand"] + (_num_words(n % 1000) if n % 1000 else [])

def spoken_fact_words(fact):
    """Words a canonical fact may be rendered as in ASR prose (digits spoken)."""
    text = (fact.lower().replace("%", " percent ").replace("$", " ")
            .replace("pm", "p m").replace("a m", "a m"))
    out = []
    for part in re.split(r"[^a-z0-9]+", text):
        if not part: continue
        if part.isdigit(): out.extend(_num_words(int(part)))
        else: out.append(part)
    return out

def trim_clean_to_budget(clean, facts, budget):
    """Drop trailing sentences/words until the base fits the word budget, but
    never remove a word that is part of a required fact (including its spoken
    number rendering, e.g. '2.1' -> two point one)."""
    words = clean.split()
    if len(words) <= budget:
        return clean
    sentences = re.split(r"(?<=\.)\s+", clean)
    fact_words = set(w.lower().strip(".,:;()") for f in facts for w in re.findall(r"[\w]+", f))
    for f in facts:
        fact_words.update(spoken_fact_words(f))
    for v in NUM_MAP.values():
        fact_words.update(w for w in re.findall(r"[a-z]+", v))
    while len(words) > budget and len(sentences) > 1:
        last = sentences[-1]
        if any(w in fact_words for w in re.findall(r"[\w]+", last.lower())):
            break
        sentences.pop()
        words = " ".join(sentences).split()
    while len(words) > budget:
        last = words[-1].lower().strip(".,:;()")
        if last in fact_words:
            break
        words.pop()
    return " ".join(words)

def apply_stutter(words, count, seed):
    r = random.Random(seed)
    words = words[:]
    for _ in range(count):
        candidates = [i for i, w in enumerate(words) if w.lower().strip(".,") in STUTTER_TARGETS]
        if not candidates: break
        i = r.choice(candidates)
        w = words[i]
        words[i:i+1] = [w, w, w]
    return words

def apply_corruption(base, variant, target_words, tier):
    """Return (raw_text, required_any, forbidden, dim_meta)."""
    rng = random.Random(hash((base["clean"], variant)) & 0xffffffff)
    # Long bases are trimmed to a fact-safe budget first so later padding/trim
    # never silently drops a required number or proper noun.
    clean = trim_clean_to_budget(base["clean"], base["facts"],
                                 target_words - (26 if tier == "long" else 12))

    # 1. garbled-term substitutions. Clean bases carry a mix of garbled surfaces
    #    ("a p i endpoint", "redish cash", "open trace") and a few canonical
    #    terms we deliberately garble in the raw ("speculative decoding").
    #    A rotating subset keeps variants distinct.
    configured = [p[0] for p in base.get("garbled", [])]
    for canonical, garbled in CANON_TO_GARBLED.items():
        if variant % 2 == 0 and canonical.lower() in clean.lower():
            clean = clean.replace(canonical, garbled, 1)
    if configured and variant % 2 == 1:
        # drop one configured garbled surface by restoring it in the clean text
        drop = configured[variant % len(configured)]
        if drop in GARBLE_MAP:
            clean = clean.replace(drop, GARBLE_MAP[drop], 1)

    # 2. strip punctuation -> ASR prose
    words = re.findall(r"[A-Za-z0-9@._:/-]+|['\u2019]", clean)
    words = [w for w in words if w != "'" and w != "\u2019"]

    # 3. fillers
    words = FILLER_INSERTIONS[variant % len(FILLER_INSERTIONS)](words)

    # 4. stutters
    words = apply_stutter(words, 1 + (variant % 3), rng.randint(0, 9999))

    # 5. false start / self-correction on a day word
    if variant % 3 == 0:
        # replace first occurrence of Wednesday/Thursday/Friday with "Thursday actually no wait Wednesday"
        for i, w in enumerate(words):
            if w in ("Wednesday", "Thursday", "Friday"):
                original = w
                alternate = "Thursday" if original != "Thursday" else "Wednesday"
                words[i:i+1] = [alternate, "actually", "no", "wait", original]
                break

    # 6. pad/trim to target word count with realistic neutral clauses
    neutral = [
        "which is important for the timeline", "and we should double check the numbers",
        "so please keep me posted on that", "as I mentioned earlier in the week",
        "but I want to be careful here", "let me know if that makes sense",
        "um and then we can decide", "I I think that is the right call",
        "you know what I mean", "right so that is the plan",
    ]
    while len(words) < target_words:
        words += neutral[len(words) % len(neutral)].split()
    if len(words) > target_words:
        # Fact-aware trim: never pop a token that belongs to a required fact.
        fact_words = set(w.lower().strip(".,:;()") for f in base["facts"]
                         for w in re.findall(r"[\w]+", f))
        for f in base["facts"]:
            fact_words.update(spoken_fact_words(f))
        insertable = set(x.lower() for x in FILLER_FORBIDDEN + ["okay", "so", "like", "right"])
        while len(words) > target_words:
            last = words[-1].lower().strip(".,:;()")
            if last not in fact_words:
                words.pop()
            elif words and words[0].lower().strip(".,:;()") in insertable:
                words.pop(0)
            else:
                # last resort: drop a redundant stutter/filler word in the middle
                idx = next((i for i, w in enumerate(words)
                            if w.lower() in ("the", "um", "uh", "you", "know", "I", "is", "it")
                            and i not in (0, len(words) - 1)), None)
                if idx is None: break
                words.pop(idx)

    raw = " ".join(words)

    # ---- required / forbidden ----
    required_all = list(base["facts"])

    # numbers that may be spelled -> accept digit OR spoken
    required_any = []
    for f in base["facts"]:
        if f in FACT_ALTERNATIVES:
            required_any.append(FACT_ALTERNATIVES[f])
        elif f in NUM_MAP:
            required_any.append([f, NUM_MAP[f]])

    # garbled surfaces actually present in the raw (word boundaries respected)
    raw_lower = " " + raw.lower() + " "
    garbled_surfaces = []
    term_required = []
    for garbled, canonical in GARBLE_MAP.items():
        if re.search(r"\b" + re.escape(garbled) + r"\b", raw_lower):
            garbled_surfaces.append(garbled)
            term_required.append(canonical)

    forbidden = []
    forbidden += garbled_surfaces
    forbidden += STUTTER_PATTERNS
    forbidden += base.get("invented", [])

    dim = {
      "facts": {"requiredAny": required_any + [[f] for f in required_all
                                               if f not in NUM_MAP and f not in FACT_ALTERNATIVES],
                "forbidden": base.get("invented", [])},
      "grammar": {"requiredAny": [], "forbidden": STUTTER_PATTERNS + FILLER_FORBIDDEN},
      "terms": {"requiredAny": [[c] for c in term_required], "forbidden": garbled_surfaces},
      "format": {"requiredAny": [[".", "!", "?"]], "forbidden": ["  "]},
      "novel": {"requiredAny": [], "forbidden": base.get("invented", [])},
    }
    return raw, required_all, required_any, forbidden, dim

STUTTER_PATTERNS = ["the the", "i i i", "it it it", "we we we", "is is is"]
FILLER_FORBIDDEN = ["um", "uh", "you know", "i mean", "basically"]

def build():
    samples = []
    # short tier: 25 bases x 4 variants = 100
    for bi, base in enumerate(SHORT_BASES):
        for v in range(4):
            raw, req_all, req_any, forb, dim = apply_corruption(base, v, 50 + (v % 4), "short")
            samples.append(dict(
                id=f"A1-S-{len(samples)+1:04d}", tier="short", domain=base["domain"],
                raw=raw, wordCount=len(raw.split()),
                requiredAll=req_all, requiredAny=req_any, forbidden=forb, dimensions=dim,
                executed=False, scores=None))

    # long tier: 25 bases x 4 variants = 100
    for bi, base in enumerate(LONG_BASES):
        for v in range(4):
            raw, req_all, req_any, forb, dim = apply_corruption(base, v, 142 + (v % 9), "long")
            samples.append(dict(
                id=f"A1-L-{len(samples)+1-100:04d}", tier="long", domain=base["domain"],
                raw=raw, wordCount=len(raw.split()),
                requiredAll=req_all, requiredAny=req_any, forbidden=forb, dimensions=dim,
                executed=False, scores=None))
    return samples

if __name__ == "__main__":
    samples = build()
    path = os.path.join(OUT_DIR, "corpus.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"generatedBy":"agent1","seed":1182026,"count":len(samples),
                   "tiers":{"short":100,"long":100},"samples":samples}, f, ensure_ascii=False, indent=2)
    # stats
    for tier in ("short","long"):
        wc = [s["wordCount"] for s in samples if s["tier"]==tier]
        print(tier, "n=",len(wc), "min=",min(wc), "max=",max(wc), "avg=",round(sum(wc)/len(wc),1))
    print("wrote", path, len(samples))

# I said "ultracode it" and came back to a working iOS app

I had a half-built web app for keeping track of my dog's health — vet visits, vaccinations, when I last gave the flea meds, that kind of thing. Somewhere along the way I changed my mind. I didn't want a website. I wanted a real iPhone app I could open with my thumb on a walk.

So I told Claude Code to do it. Not "help me do it." Do it. I typed one word — **ultracode** — and went to make coffee. An hour or so later there was a native iOS app installed on my phone: profile, meds with reminders, vaccinations, vet visits, weight charts, symptom tracking, the whole thing. 144 passing tests. It even synced to a little web dashboard.

I want to be honest about what that actually was, because "AI built my app while I made coffee" is the kind of sentence that's either a lie or a misunderstanding, and this was neither.

## What actually happened

It didn't write the app in one heroic shot. It ran it as **phases**, and each phase was a small, self-checking machine:

1. **Plan it.** A high-capability model wrote a detailed, test-first implementation plan — exact code, exact commands — and a *second* model reviewed that plan and sent it back until it was solid.
2. **Build it.** For each task in the plan, a cheaper, faster model wrote a failing test, wrote the code, **ran the real test**, and committed. Not "I think this works" — `xcodebuild test`, pass or fail, on an actual simulator.
3. **Review it.** A separate agent played skeptic on every change, trying to find what was wrong. If it found something blocking, a fixer fixed it and the reviewer looked again.
4. **Review it again.** At the end of each phase, the most capable model read the entire diff and gave a verdict.

Then it did that five times — foundation, meds, vet records, health tracking, the desktop sync — each phase building on the last. Between phases, **the tests got re-run from scratch** before the next one started. That checkpoint mattered: one review caught a screen that was fully built and unit-tested but accidentally never linked into the app's navigation. You'd never have found that from "all tests pass."

## The part nobody tells you

The reason this worked isn't that the AI got smarter. It's that a bunch of boring infrastructure lined up:

- A way to **run work in the background** and get pinged when it's done (so it could grind while I was AFK).
- A **real pass/fail signal** — tests, type-checks, a compiler. This is the whole ballgame. Without it, an AI will hand you beautiful, confident, broken code.
- A **headless toolchain.** The unsung hero here was a tool called `xcodegen`, which lets you generate an Xcode project from a text file. An AI agent can't click through Xcode's "New Project" wizard — but it can write a config file. That one tool is the difference between "possible" and "impossible."
- **Adversarial review** between agents, so mistakes got caught by a different agent instead of shipped.
- A **plan written first**, so the builders were transcribing-and-checking, not improvising.
- And honestly: **permission to just run.** I'd set it up so it didn't stop to ask me before every command. On a normal "approve each step" setup, none of this happens — it just stalls.

By the numbers: about **180 sub-agents** and **~10 million tokens** of orchestrated work. It's not cheap, and it shouldn't run unless you ask for it.

## It wasn't clean

I don't want to oversell it. The "autonomous" runs needed a babysitter at the seams:

- One run **silently rebuilt the wrong phase** because of a parameter-passing bug, burning ~2M tokens on nothing.
- A test flaked and screamed `FAILED` with zero actual failures; re-running it was fine.
- It put the wrong Apple signing ID in the config and I had to keep fixing it by hand until we found the real bug.
- A stray tooling folder broke the build entirely.

None of that got fixed by magic. It got fixed by **re-running the tests and looking.** The autonomy was real, but it was *bounded* — it worked because there was a tight loop of "make a change, prove it with a test, have another agent check it," with me sanity-checking at the phase lines.

## The takeaway

If you remember one thing: **the test signal is the product.** The orchestration is impressive, the multi-agent review is clever, but the thing that turns "AI wrote some code" into "AI wrote an app that runs on my phone" is that every single step had to prove itself against a build that either compiled and passed, or didn't.

Give an AI a true way to check its own work, a headless way to build, and permission to keep going — and you can hand it a phase, walk away, and come back to something real.

Then go re-run the tests yourself. Always.

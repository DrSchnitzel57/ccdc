# Inject & Incident Report Checklist (requirements only, so I write all the words)

## Every inject
- [ ] Read the inject **twice** and turn each requirement into a checkbox
- [ ] Interoffice memo: **To / From: Team ## / Date / Subject (include inject ID)**
- [ ] **Team number only, no real name**
- [ ] Every requirement answered, in order
- [ ] Screenshots: cropped to the evidence, **centered, labeled** ("Screenshot 1: …"), referenced in the text
- [ ] Tables labeled. One consistent font and size
- [ ] Plain language for non-technical readers (unless the audience is technical)
- [ ] Cite sources if research is involved (vendor docs, NIST, etc.)
- [ ] Spell-check. Professional tone ("Screenshot 2 shows…", not "as you can see")
- [ ] Concise, since more words don't mean more points
- [ ] Export as **PDF** named `team##_inject##.pdf`
- [ ] Submitted in Quotient **before the deadline**. Partial beats nothing
- [ ] **Zero AI-written or AI-edited text**

## Incident report: required sections
- [ ] Header addressed to leadership (CEO / CISO / Network Ops), From Team ##, Date
- [ ] Incident details: affected host, service, port, source and destination IP, timestamps, affected users
- [ ] Vulnerability exploited
- [ ] Initial access: how and when, with evidence (Splunk or log screenshot)
- [ ] Impact on the business
- [ ] Eradication: what I removed (processes, backdoors, accounts)
- [ ] Remediation: how I closed the hole so it can't recur
- [ ] Closing line offering more info
- [ ] One report per unique red-team action. Multiple reports means more points back

# IOV — Istituto Oncologico Veneto IRCCS — UOC ONCOLOGIA 1
## Shift / Guardie / Ambulatori — Operating Rules

Source: planning PDFs in `/iov/` covering the full **FEB → GIU 2026** target
period (5 consecutive months) plus MAR 2025 and MAG 2025 as 2025 reference.
Director (Direttrice): **Sara LONARDI**.

The unit shares the on-call pool, day-hospital roster and outpatient rooms with
**Oncologia 2 (ONCO 2)**. Many cells in the schedules say "ONCO 2" — that does
NOT mean the slot is empty; it means the slot for that day is covered by the
**other unit's** staff. Oncologia 1 only fills its named cells.

---

## 1. Personnel roles

There are two main roles plus ward / lab sub-rotations.

### 1.1 Specialisti (Attendings — `specialisti` PDFs)
Senior physicians who own a sub-specialty, run their dedicated outpatient
clinics, lead the multidisciplinary tumour boards, and cover the DH and the
two `reperibile` (from-home on-call) lines.

### 1.2 Specializzandi (Residents — `specializzandi` PDFs)
Trainees rotating across the unit. They are the workforce for **Prima Guardia**
and **Co-Guardia** (in-hospital on-call shifts, day & night) and they shadow
attendings in clinic.

Some residents in any given month are on **REPARTO** (ward rotation) and so
appear as `REM/REP` strings in their row — they are essentially full-time on the
inpatient ward for that block and are exempt from clinic shadowing.

### 1.3 Direttrice
**LONARDI SARA** — director. Holds a few protected `LP` (Libera Professione)
and `DP-12` slots per week; not in the guard rotation.

### 1.4 Clinic-only attendings (exempt from guardie/reperibile)
- **LONARDI Sara** — Direttrice; outpatient activity only.
- **BERGAMO Francesca** — Specialista GI (Colon sub-theme); outpatient activity
  only. Confirmed by user 2026-05: Bergamo does **NOT** participate in guardie
  or reperibile rotation despite being on the GI specialisti list.

When generating constraints, mark `in_guardie_rotation = no` for these two
people and exclude them from any reperibile / Prima Guardia / Co-guardia
assignment, even when their disease group would otherwise make them eligible.

---

## 2. Shift types (Guardie e Reperibilità)

Each `guardie XX.YYYY.pdf` is a calendar with **eight columns**, one row per day:

| Column header (Italian)            | Window                                      | Who fills it                | Notes |
|------------------------------------|---------------------------------------------|-----------------------------|-------|
| **Prima Guardia GIORNO**           | Sat/Sun/holiday 08→20                       | Resident (1st on-call, IN HOSPITAL)  | `*****` on weekdays |
| **Prima Guardia NOTTE**            | Every day 20→08                             | Resident (1st on-call, IN HOSPITAL)  | |
| **Co-Guardia GIORNO**              | Sat/Sun/holiday 08→20                       | Resident (2nd on-call, IN HOSPITAL)  | `*****` on weekdays |
| **Co-Guardia NOTTE**               | Every day 20→08                             | Resident (2nd on-call, IN HOSPITAL)  | |
| **DH MATTINO FERIALE**             | Mon–Fri 08→14                               | Attending (day-hospital lead, morning)  | single name; `*****` on weekends |
| **POMERIGGIO FERIALE 14→20 DH**    | Mon–Fri 14→20                               | Attending + resident pair (`NAME+NAME`) | `*****` on weekends |
| **REPERIBILE FASI I**              | Weekday 20→08, Holiday 08→08                | Attending — on-call from home, **FASE I** (early-phase / experimental drug) line | Many fall to ONCO 2 by rotation |
| **REPERIBILE** (standard)          | Weekday 20→08, Holiday 08→08                | Attending — on-call from home, general | |

Last column **Assenze** lists everyone absent that day (vacation, AF=permit,
AC=conference, GG=Genitori-figli leave, GN/SN=post-shift recovery, etc.).
Lowercase names = ONCO 1 staff absences carried forward into the planner.

### 2.1 Daily composition
- **Weekday (Mon–Fri):** 1 night 1st-guard (R) + 1 night co-guard (R) + 1 DH
  morning attending + 1 DH afternoon attending (paired with 1 resident) +
  1 FASI-I reperibile + 1 standard reperibile.
- **Weekend / public holiday:** 1 day 1st-guard (R, 08–20) + 1 day co-guard (R,
  08–20) + 1 night 1st-guard (R) + 1 night co-guard (R) + 2 reperibili. **No DH.**

### 2.2 Cross-unit pool
Both ONCO 1 and ONCO 2 residents feed the same guard pool. Names from ONCO 2
that recur in the guardie schedules but never appear in the ONCO 1 specialisti
or specializzandi files (e.g. CACCO, CARTURAN, CASALE, LA COMMARE, PALMISANO,
NAPOLITANO, NAPETTI, BONOMI, SANGIORGI, TROVO', LANDA, PALMISANO, BLOISE,
VITALE, SPANO, GASPARI, MASSA, MAZZALVERI, DI DOMENICO, DI NAPOLI, ALAIBAC,
PACILLI, SARTORI E. / SARTORI B., BIVONA, POZZEBON, BRAVI, TRITONI*) are pulled
from the ONCO 2 register. *(TRITONI was an ONCO 1 ward resident in Apr 2026 — name
collisions are possible.)*

Some attending shifts also rotate to ONCO 2 — when a row's DH or reperibile cell
reads "ONCO 2", that slot is covered by an ONCO 2 attending and no ONCO 1
attending is needed.

### 2.3 Special tags inside attending / resident rows (`specialisti` + `specializzandi` files)
- `REM` (matt) / `REP` (pom) — REPARTO: that person is on the inpatient ward.
- **`GM` — Guardia Mattina**: that person is the morning DH guard that day
  (= corresponds to the `dh_mattino_feriale` cell in the guardie file).
- **`GP` — Guardia Pomeriggio**: that person is the afternoon DH guard that
  day (= corresponds to one half of the `pomeriggio_feriale` pair).
  GP / GM in a prospetto row are cross-references to the guardie file, NOT
  off-days.
- `RA` — Riunione Aziendale / management meeting.
- `LP` — **Libera Professione** (private-practice clinic session by the attending).
- `DP-…` — Day Pavilion / DH slot in a numbered ambulatorio.
- `PV-1…PV-7` — Prime Visite (new-patient slots) by AMB number.
- `FU-…` — Follow-up slots.
- `CER`, `URO`, `PROS`, `COLON`, `PAN`, `SAR`, `NET`, `UPPER`, `CEB`, `ERED`,
  `FT-GI`, `FT-S`, `FT-U` — disease-group multidisciplinary or focused clinic.
- `OO` — Orario Ospedaliero alternativo (alternative hospital schedule).
- `MTB` — Molecular Tumor Board.
- `CARCI` — Carcinosi peritoneale clinic.
- `EG` — Endoscopia / Esame Gastroenterologico shadow slot.
- `GN`/`SN` — Giornata Notte / Smonto Notte (post-night-shift recovery — the
  resident is OFF the next day after a NOTTE guard).
- `AF` / `AC` / `GG` — absence markers (Assenza Ferie / Assenza Convegno /
  Genitori-Giorni leave). Lowercase versions of these appear in the `Assenze`
  column of the guardie file.

---

## 3. Disease groups (sotto-gruppi tematici)

The ONCO 1 attendings are partitioned by disease group. The `prospetto
ambulatori X.YYYY.pdf` shows the weekly grid; the rules below are stable across
Feb/Apr/May/Jun 2026.

### 3.1 GASTROENTERICO (GI) — largest group
Attendings: **NAPPO Floriana, PROCACCIO Letizia, DE GRANDIS Caterina, SOLDA'
Caterina, MURGIONI Sabina, CERMA Krisida, MADDALENA Giulia, INTINI Rossana,
RIZZATO Mario, NICHETTI Federico, BERGAMO Francesca** (+ junior attending
**DE ROSA Antonio** from Apr 2026).
Sub-themes carried by GI attendings:
- HCC / Epatobiliare → SOLDA', RIZZATO (alternated)
- Pancreas → PROCACCIO, NICHETTI
- NET / Upper GI → MURGIONI
- Carcinosi → NAPPO
- Colon-Retto / Multi RETTO → BERGAMO, MADDALENA, DE GRANDIS, INTINI
- Tumori Ereditari → INTINI (Q2 weeks)

### 3.2 UROLOGICO (GU)
Attendings: **BASSO Umberto, ZAMPIVA Ilaria, BIMBATTI Davide**.
- AMB 3 Mon: BASSO / AMB 3 Tue: ZAMPIVA
- AMB 12 Tue (URO): BIMBATTI
- AMB 4 Fri: ZAMPIVA
- GOM PROSTATA Fri 13:30–15: BASSO + BIMBATTI + Di Marco

### 3.3 CEREBRALI (CNS)
Attendings: **CACCESE Mario, LOMBARDI Giuseppe, PADOVAN Marta** (+ junior
attending **MACCARI Marta** with mostly LAB rotation, from Apr 2026).
- AMB 3 Wed: CACCESE
- AMB 3 Thu: LOMBARDI
- AMB 3 Fri: PADOVAN
- AMB 16 Mon: CACCESE (CER)
- SURRENE / IPOFISI Fri (monthly): LOMBARDI
- GOM CEREBRALI Thu 13–15: LOMBARDI + CACCESE

### 3.4 SARCOMI
Attendings: **BRUNELLO Antonella, CHIUSOLE Benedetta, TORTORELLI Ilaria**.
- AMB 4 Tue (SAR): BRUNELLO
- AMB 7 Mon (SAR): CHIUSOLE
- AMB 2 Wed (SAR): CHIUSOLE
- AMB 12 Thu (SAR): TORTORELLI
- OSTEONCOLOGIA Mon: BRUNELLO
- GOM SARCOMI Thu: BRUNELLO + CHIUSOLE

### 3.5 CURE SIMULTANEE (Supportive / Palliative)
Attending: **TORTORELLI Ilaria** (AMB 16 Wed 8:30–13:30, plus FT-S follow-up).

### 3.6 ~~ONCO-EMATOLOGICO~~ — group no longer exists at IOV (user-confirmed)
The Onco-Ematologico sub-specialty is **gone** from Oncologia 1's structure.
Do NOT model it as a disease group. The 2025 attendings Marino and Finotto
have left. The `ONCO EMATOLOGICO` labels still printed on AMB 4 Mon/Wed/Thu
in the 2026 prospetti are historical artifacts; treat those slots as
non-existent for ONCO 1 scheduling purposes.

### 3.7 REPARTO (Inpatient ward — full-time attendings)
Permanent: **GALIANO Antonella, BOLSHINSKY Maital**.
Rotating residents on ward (one block of 4 per month, per prospetto):
- Feb 2026: Sperotto, Gaion, Sartorello, Stocco
- Mar 2026: Bosa, Mario (Elena), Sartori (Beatrice), Tritoni (Daniele)
- Apr 2026: Gaiani, Gaion, Sartorello, Stocco *(prospetto says "Gaiani, Gaion, Sartorello, Stocco"; spec file shows Mario / Sartori / Tritoni / Bianchi still on REM rotation through this block)*
- May 2026: Di Paolo, Mario, Sartori, Bianchi
- Jun 2026: Bosio, Mario, Tritoni, Bianchi (per individual schedules)

---

## 4. Outpatient room map (Ambulatori)

The unit has 8 rooms. Each room has a fixed phone extension and a weekly theme
assignment that has been stable from Feb 2026 onward. Source: prospetto
ambulatori MAG/GIU 2026 (the cleanest template).

| Room | Tel  | Mon                | Tue                | Wed                | Thu                | Fri                |
|------|------|--------------------|--------------------|--------------------|--------------------|--------------------|
| AMB 1| 5899 | GI — NAPPO         | GI — PROCACCIO     | GI — DE GRANDIS    | GI — NAPPO         | GI — PROCACCIO     |
| AMB 2| 5906 | GI — SOLDA'        | GI — MURGIONI      | SARCOMI — CHIUSOLE | GI — CERMA         | GI — MADDALENA     |
| AMB 3| 5918 | URO — BASSO        | URO — ZAMPIVA      | CER — CACCESE      | CER — LOMBARDI     | CER — PADOVAN      |
| AMB 4| 5905 | —                  | SAR — BRUNELLO     | —                  | —                  | URO — ZAMPIVA      |
| AMB 6| 5536 | GI — MADDALENA     | GI — INTINI        | GI — SOLDA'        | GI — RIZZATO       | GI — INTINI        |
| AMB 7| 5195 | SAR — CHIUSOLE     | GI — CERMA         | URO — BIMBATTI     | GI — NICHETTI      | GI — RIZZATO       |
| AMB 12| 5564| ONCO 2             | URO — BIMBATTI     | GI — BERGAMO       | SAR — TORTORELLI   | ONCO 2             |
| AMB 16| 5283| CER — CACCESE      | ONCO 2             | CURE SIM. — TORT.  | ONCO 2             | UPPER GI — MURGIONI|

Afternoon slots use the same rooms but switch to disease-specific themes
(GU FU 0404, GI prime visite 0416, pancreas 0433, CER FU 0423, HCC 0431, etc.).
Each clinic is staffed by **1 attending + 1 resident** unless the room is
allocated to ONCO 2.

### 4.1 Multidisciplinari (Tumour boards)
- **Mon AM**: Osteoncologia 12:30–14:30 — BRUNELLO
- **Mon PM**: GOM Urologico AOPD 15:30–17 — BIMBATTI / Di Marco
            GOM Upper GI 16–17:30 — MURGIONI (sometimes shifted to Thu)
- **Tue AM**: Multi Carcinosi 8–9:30 — NAPPO
- **Tue PM**: GOM Retto 14:30–15:30 + Colon 15:30–18 — BERGAMO + (MADDALENA or
             DE GRANDIS)
- **Wed PM**: GOM Tumori Ereditari 15–16 (Q2 wks) — INTINI
- **Thu AM**: GOM Sarcomi 8–10 — BRUNELLO + CHIUSOLE
            Multi Retto 8:30–13:30 — INTINI
            GOM Urologico IOV 8:30–10 — BASSO + ZAMPIVA
            MTB 13–14 — MADDALENA
- **Thu PM**: GOM Cerebrali 13:30–15 — LOMBARDI + CACCESE
            GOM Pancreas 14–15:15 — PROCACCIO + NICHETTI
            Multi NET 15–16:30 — MURGIONI
            GOM NET 17–19 — MURGIONI
            GOM Epatobiliare 15:30–17 — SOLDA' **alternato** RIZZATO
- **Fri AM**: Surrene/Ipofisi 13:45–14:45 (monthly) — LOMBARDI
- **Fri PM**: GOM Prostata 13:30–15 — BASSO + BIMBATTI + Di Marco

---

## 5. Constraints that drive the scheduler

These are the constraints that any ShiftHappens implementation must encode.

1. **One resident never does two consecutive nights.** After a night first-guard
   (NOTTE 20→08) or co-guard, the next day shows `GN`/`SN` in the resident's
   prospetto row (post-night recovery).
2. **A resident on REPARTO that month does not fill guards** outside the ward
   block (their row is solid `REM/REP`).
3. **Weekend coverage is a 4-tuple** (1st day, co day, 1st night, co night).
   The 4 residents must be different people; typically 2 from ONCO 1 + 2 from
   ONCO 2 (or any mix, but always 4 distinct).
4. **Attending coverage on a weekday** requires 4 ONCO 1 names (DH morning,
   DH afternoon attending part of pair, Reperibile FASI I, Reperibile) unless
   any of those cells rotates to ONCO 2.
5. **DH afternoon pair** = 1 attending + 1 resident; the attending must be
   from the same disease group as the day's clinic theme when possible.
6. **Reperibile FASI I requires a Phase-I-credentialed attending.** Names
   observed in this column: INTINI, BOLSHINSKY, CACCESE, SOLDA', LOMBARDI,
   BASSO, BIMBATTI — a smaller subset than the general reperibile.
7. **Absences (`Assenze` column) are inputs, not outputs** — the scheduler
   reads them and must avoid assigning anyone listed there that day.
8. **Holidays count as weekends** for the guardie pattern (eight-cell row with
   day shifts populated and DH `*****`).
9. **Cross-unit rotation**: any day a column reads `ONCO 2`, the ONCO 1 side
   contributes zero people to that cell. The reverse holds for ONCO 2's own
   roster — they see "ONCO 1" cells on the days we fill it.
10. **The director (LONARDI)** holds a fixed weekly `LP` and `DP-12` footprint
    (4 LP + 1 DP-12 per week, ~20–25 hours/month) and is not assigned guardie.

---

## 6. Naming conventions / quirks

- Attending names are uppercase in the guardie file (e.g. `BIMBATTI`,
  `LOMBARDI`), residents tend to appear mixed-case in the `prospetto
  ambulatori` (e.g. `Bertin`, `Palescandolo`). In the `guardie` file all names
  are uppercase regardless.
- Apostrophes drop or move: `SOLDA'` vs `SOLDA`, `TROVO'` vs `TROVO`.
- Typos in source PDFs include: `NAPOLITNO` (Feb 12 — should be NAPOLITANO),
  `brergamo` (Apr 22), `SARTORI E` vs `SARTORI B` (two different Sartoris on
  the ONCO 2 side: SARTORI ELENA and SARTORI BEATRICE).
- `CHIUSOLE` appears as a name in ONCO 1 (Benedetta — sarcoma attending) and
  occasionally in guardie covering night shifts — same person.

---

## 7. Data coverage in `/iov/`

| Folder                                  | Has              | Notes |
|-----------------------------------------|------------------|-------|
| bozzaturnieguardiefebbraio2026          | All 4 files      | FEB 2026 ✅ |
| bozzaturnieguardiemarzo2026             | All 4 files      | MAR 2026 ✅ |
| bozzaturnieguardieaprile2026            | All 4 files      | APR 2026 ✅ |
| bozzaturnieguardiemaggio2026            | All 4 files      | MAG 2026 ✅ |
| bozzaturnieguardiegiugno2026            | All 4 files      | GIU 2026 ✅ (prospetto file inside this folder is internally titled "MAGGIO 2026" — clerical mis-label; cross-checked against the dedicated May folder) |
| bozzaturnieguardiemarzo2025             | 2025 — reference  | Historical comparison only |
| bozzaturnieguardiemaggio2025            | 2025 — reference  | Historical comparison only |

**Staff turnover** between 2025 reference data and 2026 active months:
- **No longer at IOV** (user-confirmed, do NOT include in any 2026 schedule):
  Marino, Finotto (Onco-Emato attendings — group now covered by ONCO 2);
  Jubran, Zen, Cerantola, Ricagno, Perissinotto, Erbetta (residents who
  graduated or moved on). Surnames matching some of these (Vitale, Baldan,
  Di Domenico, Alaibac) DO appear in 2026 guardie — those are ONCO 2
  residents in the shared pool, NOT the former ONCO 1 trainees.
- **New in 2026**:
  - **De Rosa Antonio** — now a full Specialista (user-confirmed). First
    appears in the Mar 2026 specialisti file in the GI group with HCC
    sub-theme alongside Solda'/Rizzato.
  - **Maccari Marta** — graduated from resident to junior attending; primary
    rotation is LAB plus AMB 3 Wed/Thu cerebrali.
  - Bianchi (Roberto), Mario (Elena), Tritoni (Daniele), Sartori (Beatrice) —
    new residents from Mar 2026.
  - Biondi (Arianna) — new resident from May 2026.
- **Left mid-2026**: Giammatteo (resident) appears in Feb-Apr 2026 but is
  absent from May & Jun 2026 specializzandi files.

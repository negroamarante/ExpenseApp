---
name: code-review
description: Review changes to the ExpenseApp Salesforce project (Apex, LWC, metadata, scripts, workflows). Use when reviewing a pull request, a diff, or uncommitted changes in this repo.
---

# ExpenseApp code review

Family budget app on Salesforce. Two views share the same `Expense__c` records and must stay separate:

- **Límite cupo** (`budgetDashboard`, `BudgetController`): expenses with `Counts_Toward_Budget__c = true`, checked against `Monthly_Budget__c` (committed, rollover, available).
- **Gastos mensuales** (`spendingDashboard`, `SpendingController`): expenses with `Counts_Toward_Spending__c = true`, just a monthly total. No budget, no rollover.

An expense can count toward both. Data model: `docs/object-model.md`.

## Check first: the two views never leak into each other

- Any query over `Expense_Installment__c` or `Expense__c` that feeds one view filters by that view's flag (`Expense__r.Counts_Toward_Budget__c` or `Expense__r.Counts_Toward_Spending__c`). A missing filter makes spending expenses show up in Límite cupo, or inflates `Committed__c`.
- `ExpenseInstallmentService.recalculateFrom` sums only installments of expenses that count toward the budget.
- `expenseFormModal` only writes the flags it owns: budget mode sets them on create only, spending mode sets them from its own checkbox. Editing must never clear a flag the form doesn't show.
- Monthly totals use the installment amount of that month (`Expense_Installment__c.Amount__c`), not `Total_Amount__c`.

## Apex

- Bulk-safe: no SOQL or DML inside loops. Triggers can receive 200 records.
- `ExpenseInstallmentService` uses the static `isRunning` guard to avoid recursion between `ExpenseTrigger` and `MonthlyBudgetTrigger`. New write paths set it in `try` and reset it in `finally`.
- If a field that affects installments changes (date, amount, number of installments, budget flag), it is listed in `fieldsChanged`.
- Controllers called from LWC use `with sharing` and `WITH USER_MODE`.
- `@AuraEnabled(cacheable=true)` methods only read. Writes go through LDS or non-cacheable methods.
- Every Apex change comes with a test. Prefer assertions on stored fields (`Committed__c`, `Rollover_In__c`, installment rows) over only checking the controller output.
- Gemini callouts go through `GeminiClient` and are mocked in tests with `HttpCalloutMock`.

## LWC

- After a save or delete, the dashboard refreshes its wire with `refreshApex`. The month-change flow in `budgetDashboard` relies on `pendingRefresh`; keep it.
- Picklist values come from `getPicklistValues`, not hardcoded lists.
- User-facing text is in Spanish (Argentina), amounts in ARS.
- Jest tests mock Apex and `lightning/modal`; new behavior in `expenseFormModal` or the dashboards gets a test.

## Metadata

- A new field needs: field-level access in `Presupuesto_Familiar_Acceso`, and a layout entry if users edit it.
- A new tab needs: the app (`Presupuesto_Familiar`) and a `tabSettings` entry in the permission set.
- `Person__c` is a restricted picklist (`Diego`, `Emi`). Code that sets it must use those exact values; the receipt scan defaults to `Emi`.
- Don't add `Installments__r` related lists to layouts via metadata: the deploy fails. That list is added in App Builder.
- Checkbox defaults only apply to new records. If a change depends on existing records having a value, the PR says how they get it.

## Secrets and orgs

- No API keys, auth URLs, or usernames of other people in code. The Gemini key lives in the `Api_Key_Store__c` custom setting, set by hand per org.
- The Email Service (`emailservices/`) has the production user as `runAsUser`, so scratch deploys exclude it (`scripts/verify-scratch.sh`, `scripts/setup-scratch-dev.sh`). Scratch orgs use `scripts/setup-scratch-email.sh`.
- `.github/workflows/deploy.yml` deploys `force-app` to the Developer Org on every push to `main` with `RunLocalTests`. Flag anything that could break that deploy (failing tests, metadata that only works in scratch).

## How to report

Group findings by severity: bugs first (data leaking between views, wrong totals, failing deploys), then missing tests, then style. For each one, give file and line, what goes wrong for the family using the app, and the fix. Skip nits Prettier or ESLint already catch.

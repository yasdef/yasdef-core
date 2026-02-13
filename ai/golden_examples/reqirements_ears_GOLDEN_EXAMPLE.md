# Requirements (EARS) - Golden Example

This example is synthetic and project-agnostic.

System name: Example Task Tracking Service (“ETTS”)  
Scope: REST API + database-backed task tracking with auditable state changes.

---

## Overview
- Product/Domain: Example task tracking system
- Goals: Create, update, and query tasks with auditable state changes
- Out of scope: Billing, multi-tenant org management

## Glossary
- Task: A unit of work tracked by the system
- Assignee: The user responsible for a task

## Actors
- User: End user interacting with the system
- Admin: Operator managing configuration

## Assumptions
- Users authenticate before accessing protected endpoints.
- Time is recorded in UTC.

---

## Requirements

### Requirement 1 — Create tasks
**User Story:** As a user, I want to create a task with a title and due date, so that I can track work I need to complete.

**Acceptance Criteria (EARS):**
- WHEN a user submits a create-task request, THE Example Task Tracking Service SHALL create a new task with the provided title and due date.
- WHEN a task is created, THE Example Task Tracking Service SHALL record an immutable creation timestamp for that task.
- IF a create-task request is missing a title, THEN THE Example Task Tracking Service SHALL reject the request with a validation error.

**Verification:** API tests for `POST /tasks` success and validation failures; database assertions for stored timestamps.

---

### Requirement 2 — Prevent edits after completion
**User Story:** As a user, I want completed tasks to be immutable, so that “done” work is not accidentally changed.

**Acceptance Criteria (EARS):**
- WHILE a task is in state `DONE`, THE Example Task Tracking Service SHALL reject requests that modify the task title.
- WHEN a user attempts to modify a `DONE` task, THE Example Task Tracking Service SHALL return a deterministic error code indicating the task is not editable.

**Verification:** API tests for `PATCH /tasks/{id}` against tasks in `DONE`.

---

### Requirement 3 — Reminder notifications (optional feature)
**User Story:** As a user, I want optional reminders, so that I do not miss due dates.

**Acceptance Criteria (EARS):**
- WHERE reminders are enabled, WHEN a task is due within 24 hours, THE Example Task Tracking Service SHALL enqueue a reminder notification for the task assignee.

**Verification:** Integration test that enables reminders and asserts a notification is enqueued for an eligible task.

---

### Requirement 4 — Delete behavior for missing tasks
**User Story:** As a client developer, I want consistent not-found responses, so that I can handle deletes predictably.

**Acceptance Criteria (EARS):**
- IF a user attempts to delete a task that does not exist, THEN THE Example Task Tracking Service SHALL return HTTP 404.

**Verification:** API test for `DELETE /tasks/{id}` with a non-existent id.

---

## Non-Functional Requirements

### NFR 1 — Query latency
**User Story:** As a user, I want task queries to be fast, so that the UI feels responsive.

**Acceptance Criteria (EARS):**
- THE Example Task Tracking Service SHALL return `GET /tasks` responses within 300 ms at p95 under the defined test load.

**Verification:** Load test report and CI performance gate for p95 latency.

---

## END OF EARS SPECIFICATION (GOLDEN EXAMPLE)

"use client";

import { type FormEvent, useEffect, useState } from "react";
import styles from "./waitlist-form.module.css";

type Status = "idle" | "loading" | "success" | "error";

const STORAGE_KEY = "ps_waitlist_joined";

export function WaitlistForm() {
  const [email, setEmail] = useState("");
  const [teacher, setTeacher] = useState(false);
  const [newsroom, setNewsroom] = useState(false);
  const [status, setStatus] = useState<Status>("idle");
  const [message, setMessage] = useState("");

  useEffect(() => {
    try {
      if (localStorage.getItem(STORAGE_KEY) === "1") {
        setStatus("success");
        setMessage(
          "You're already on the list. We'll email you when betas open.",
        );
      }
    } catch {
      // ignore
    }
  }, []);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setStatus("loading");
    setMessage("");

    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email,
          roles: [
            ...(teacher ? (["teacher"] as const) : []),
            ...(newsroom ? (["newsroom"] as const) : []),
          ],
        }),
      });
      const data = (await res.json()) as {
        ok?: boolean;
        error?: string;
      };

      if (!res.ok || !data.ok) {
        setStatus("error");
        setMessage(data.error ?? "Something went wrong. Try again.");
        return;
      }

      try {
        localStorage.setItem(STORAGE_KEY, "1");
      } catch {
        // ignore
      }

      // One message for both cases on purpose. The route no longer reports
      // whether the address was already on the list — telling the submitter
      // apart from a stranger probing addresses is not possible, so nobody is
      // told. The returning-visitor copy above is driven by localStorage,
      // which only the person who signed up on this device has.
      setStatus("success");
      setMessage(
        "You're on the list. We'll email you when iOS and Android betas open.",
      );
      setEmail("");
    } catch {
      setStatus("error");
      setMessage("Network error. Check your connection and try again.");
    }
  }

  if (status === "success") {
    return (
      <p className={styles.success} role="status">
        {message}
      </p>
    );
  }

  return (
    <form className={styles.form} onSubmit={onSubmit} noValidate>
      <label className="srOnly" htmlFor="waitlist-email">
        Email
      </label>
      <input
        id="waitlist-email"
        name="email"
        type="email"
        autoComplete="email"
        required
        inputMode="email"
        placeholder="you@email.com"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        disabled={status === "loading"}
      />
      <button type="submit" disabled={status === "loading"}>
        {status === "loading" ? "Joining…" : "Join the waitlist"}
        {status !== "loading" ? (
          <span className={styles.arrow} aria-hidden="true">
            →
          </span>
        ) : null}
      </button>
      {status === "error" ? (
        <p className={styles.error} role="alert">
          {message}
        </p>
      ) : null}
      <fieldset className={styles.roles}>
        <legend className={styles.rolesLegend}>
          Optional — tell us who you are
        </legend>
        <label className={styles.role}>
          <input
            type="checkbox"
            checked={teacher}
            onChange={(e) => setTeacher(e.target.checked)}
            disabled={status === "loading"}
          />
          I’m a teacher or professor
        </label>
        <label className={styles.role}>
          <input
            type="checkbox"
            checked={newsroom}
            onChange={(e) => setNewsroom(e.target.checked)}
            disabled={status === "loading"}
          />
          I work at a newsroom or civic organization
        </label>
      </fieldset>
      <p className={styles.privacy}>
        Launch notes only. No spam. Unsubscribe anytime.
      </p>
    </form>
  );
}

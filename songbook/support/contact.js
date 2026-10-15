"use strict";

const form = document.getElementById("contact-form");
const statusText = document.getElementById("contact-status");
const submit = document.getElementById("contact-submit");
submit.disabled = false;

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!form.reportValidity()) return;
  submit.disabled = true;
  submit.textContent = "Sending…";
  statusText.textContent = "";
  const fields = new FormData(form);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch(form.action, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json" },
      credentials: "omit",
      signal: controller.signal,
      body: JSON.stringify({ contact_enquiry: {
        name: fields.get("name").trim(),
        email: fields.get("email").trim(),
        subject: "Misia Songbook support",
        message: fields.get("message").trim(),
        website: fields.get("website").trim()
      } })
    });
    if (response.status === 429) {
      statusText.textContent = "Too many messages. Please try again in 10 minutes or email info@misia.sk.";
      return;
    }
    if (response.status !== 202) throw new Error("Message not accepted");
    const result = await response.json();
    if (result.status !== "accepted") throw new Error("Unexpected response");
    statusText.textContent = "Your message has been accepted by Misia's support server. Thank you.";
    form.reset();
  } catch (_) {
    statusText.textContent = "Your message could not be confirmed as sent. Your text is still here. Please try later or email info@misia.sk.";
  } finally {
    clearTimeout(timeout);
    submit.disabled = false;
    submit.textContent = "Send message";
  }
});

/* ==========================================================================
   The correction form's progressive enhancement. SHELL.md r9.

   THE FORM ALREADY WORKS WITHOUT THIS FILE. It is a real <form action> with
   method="POST" to Formspree, so deleting this script costs the visitor an
   inline reply and nothing else — which is the same standard the rest of the
   page holds itself to.

   The one rule that matters here: "sent" is printed ONLY after the endpoint
   actually returns 2xx. A form that says thank-you on submit and drops the
   message is precisely the failure this page exists to argue against, and it
   is the default behaviour of most hand-rolled AJAX forms.
   ========================================================================== */
(function () {
    var form = document.querySelector("form.say");
    if (!form || !window.fetch || !window.FormData) return;
    var msg = form.querySelector(".say-msg");
    var btn = form.querySelector("button[type=submit]");
    if (!msg || !btn) return;

    function say(text, cls) {
        msg.textContent = text;
        msg.className = "say-msg" + (cls ? " " + cls : "");
    }

    form.addEventListener("submit", function (e) {
        /* checkValidity is ours to call because the form carries novalidate:
           the browser's own bubbles are styled by the browser, not by us. */
        if (!form.checkValidity()) {
            e.preventDefault();
            var bad = form.querySelector(":invalid");
            say(bad && bad.name === "email" ? "That email address will not parse." : "Both fields are needed.", "bad");
            if (bad) bad.focus();
            return;
        }
        e.preventDefault();
        btn.disabled = true;
        say("sending…");

        fetch(form.action, {
            method: "POST",
            body: new FormData(form),
            headers: { Accept: "application/json" },
        })
            .then(function (res) {
                return res.json().then(
                    function (data) { return { ok: res.ok, status: res.status, data: data }; },
                    function () { return { ok: res.ok, status: res.status, data: null }; }
                );
            })
            .then(function (r) {
                if (r.ok) {
                    form.reset();
                    say("Sent. A person reads these; give it a day or two.", "ok");
                    /* Re-enabled so a second, different message is possible without
                       a reload; the reset form cannot resend the first one, because
                       empty fails validation. */
                    btn.disabled = false;
                    return;
                }
                /* Report what the endpoint actually said, not a generic apology —
                   the reason is usually actionable. */
                var why =
                    (r.data &&
                        (r.data.error ||
                            (r.data.errors && r.data.errors.map(function (x) { return x.message; }).join("; ")))) ||
                    "HTTP " + r.status;
                say("Not sent — " + why, "bad");
                btn.disabled = false;
            })
            .catch(function () {
                /* The network, an extension, or a blocked third party. Say so rather
                   than leaving the button spinning on a lie. */
                say("Not sent — the request never completed. Check the connection, or anything blocking formspree.io.", "bad");
                btn.disabled = false;
            });
    });
})();

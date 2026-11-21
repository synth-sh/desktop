enum BrowserPageScript {
    static let source = #"""
    const ok = content => ({ content });
    const fail = content => ({ content, isError: true });
    const normalize = text => text.trim().replace(/\s+/g, " ");
    const state = globalThis.synthBrowser ??= {
        prefix: crypto.getRandomValues(new Uint32Array(2)).join("-"),
        ids: new WeakMap(),
        refs: new Map(),
        nextID: 1
    };

    function visible(element) {
        if (element.closest("[hidden], [inert], [aria-hidden=true]")) return false;
        const bounds = element.getBoundingClientRect();
        return bounds.width > 0 && bounds.height > 0 && getComputedStyle(element).visibility === "visible";
    }

    function inViewport(element) {
        const bounds = element.getBoundingClientRect();
        return bounds.bottom > 0 && bounds.right > 0 && bounds.top < innerHeight && bounds.left < innerWidth;
    }

    function label(element) {
        const labelledBy = (element.getAttribute("aria-labelledby") ?? "").split(/\s+/)
            .map(id => document.getElementById(id)?.textContent ?? "").join(" ").trim();
        const labels = Array.from(element.labels ?? [], item => item.innerText ?? "").join(" ").trim();
        return normalize(element.getAttribute("aria-label") || labelledBy || labels ||
            element.getAttribute("placeholder") || element.innerText || element.getAttribute("title") ||
            element.getAttribute("alt") || element.getAttribute("name") || "").slice(0, 160);
    }

    function describe(element) {
        const tag = element instanceof HTMLInputElement ? element.type : element.localName;
        const kind = element.getAttribute("role") || tag;
        const details = [kind];
        const name = label(element);
        if (name) details.push(JSON.stringify(name));
        if (element.matches(":disabled, [aria-disabled=true]")) details.push("(disabled)");
        if (element instanceof HTMLInputElement && ["checkbox", "radio"].includes(element.type)) {
            details.push(element.checked ? "(checked)" : "(unchecked)");
        }
        if (element instanceof HTMLSelectElement) {
            const options = Array.from(element.options).slice(0, 20).map(item => ({
                value: item.value.slice(0, 100),
                label: normalize(item.label).slice(0, 100),
                selected: item.selected
            }));
            details.push(JSON.stringify(options));
        }
        return details.join(" ").slice(0, 500);
    }

    function snapshot() {
        const controls = document.querySelectorAll(
            "a[href], button, input:not([type=hidden]), select, textarea, summary, [contenteditable=true], " +
            "[role=button], [role=link], [role=checkbox], [role=radio], [role=tab], [role=textbox], [role=combobox]"
        );
        state.refs.clear();
        const items = [];
        let itemCharacters = 0;
        for (const element of controls) {
            if (!visible(element) || !inViewport(element)) continue;
            if (!state.ids.has(element)) state.ids.set(element, state.prefix + "-" + state.nextID++);
            const id = state.ids.get(element);
            state.refs.set(id, new WeakRef(element));
            const item = "[" + id + "] " + describe(element);
            items.push(item);
            itemCharacters += item.length;
            if (items.length >= 60 || itemCharacters >= 4200) break;
        }
        const text = document.body?.innerText?.trim() ?? "";
        const page = "URL: " + location.href.slice(0, 1000) + "\nTitle: " + document.title.slice(0, 250);
        const position = "Viewport scroll: " + Math.round(scrollY) + " / " +
            Math.max(0, (document.scrollingElement?.scrollHeight ?? innerHeight) - innerHeight);
        const content = text.slice(0, 4200) + (text.length > 4200 ? "\n[Page text truncated]" : "");
        const sections = [page, position, "Controls in viewport:\n" + items.join("\n"), "Page text:\n" + content];
        return ok(sections.join("\n\n"));
    }

    function fill(element, value) {
        const textInputTypes = ["text", "search", "email", "url", "tel", "number"];
        if (element instanceof HTMLInputElement && textInputTypes.includes(element.type)) {
            if (element.readOnly) return fail("The field is read-only.");
            Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(element, value);
        } else if (element instanceof HTMLTextAreaElement) {
            if (element.readOnly) return fail("The field is read-only.");
            Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value").set.call(element, value);
        } else if (element instanceof HTMLSelectElement) {
            if (!Array.from(element.options).some(option => option.value === value && !option.matches(":disabled"))) {
                return fail("Choose an enabled option value from the snapshot.");
            }
            Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, "value").set.call(element, value);
        } else if (element.isContentEditable) {
            element.textContent = value;
        } else {
            return fail("This control cannot be filled. Use the browser tab to enter the value manually.");
        }
        element.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
        return ok("Updated the control.");
    }

    if (operation === "snapshot") return snapshot();
    if (operation === "scroll") {
        if (direction !== "up" && direction !== "down") return fail("Choose up or down.");
        window.scrollBy({ top: innerHeight * (direction === "up" ? -0.85 : 0.85), behavior: "instant" });
        return ok("Scrolled. Take a fresh snapshot to see the controls in view.");
    }

    const element = state.refs.get(ref)?.deref();
    if (!element?.isConnected || !visible(element)) return fail("The element reference is stale. Take a new snapshot.");
    if (element.matches(":disabled, [aria-disabled=true]")) return fail("The control is disabled.");
    if (element instanceof HTMLInputElement && element.type === "file") {
        return fail("Choose files manually in the browser tab.");
    }
    element.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "instant" });
    if (operation === "fill") return fill(element, text);
    element.click();
    return ok("Clicked the control. Take a new snapshot to verify the result.");
    """#
}

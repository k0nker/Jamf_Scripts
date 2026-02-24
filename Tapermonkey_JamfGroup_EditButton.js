// ==UserScript==
// @name         Jamf Group Quick Edit Links
// @version      2026-02-24
// @description  Adds Edit links next to Jamf computer groups
// @author       k0nker
// @match        *://*.jamfcloud.com/*
// @icon         https://www.google.com/s2/favicons?sz=64&domain=tampermonkey.net
// @grant        none
// @namespace    jamf
// ==/UserScript==

(function() {
    'use strict';

    function addEditLinks() {
        const links = document.querySelectorAll(
  'a[href*="staticComputerGroups.html"][href*="o=r"], a[href*="smartComputerGroups.html"][href*="o=r"]'
);

        links.forEach(link => {
            if (link.dataset.editAdded) return;

            const editLink = link.cloneNode(true);
            editLink.href = link.href.replace('o=r', 'o=u');
            editLink.textContent = 'Edit';
            editLink.style.background = '#007bff';
            editLink.style.color = '#fff';
            editLink.style.padding = '2px 6px';
            editLink.style.borderRadius = '4px';
            editLink.style.fontSize = '12px';
            editLink.style.cursor = 'pointer';
            editLink.style.textDecoration = 'none';
            editLink.target = '_blank';
            const parent = link.parentElement;
            parent.style.display = 'flex';
            parent.style.justifyContent = 'space-between';
            parent.style.alignItems = 'center';
            parent.appendChild(editLink);
            link.dataset.editAdded = "true";
        });
    }

    // Jamf loads dynamically sometimes, so retry a few times
    const observer = new MutationObserver(addEditLinks);
    observer.observe(document.body, { childList: true, subtree: true });

    // Initial run
    addEditLinks();
})();
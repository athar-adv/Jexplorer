// Populate the sidebar
//
// This is a script, and not included directly in the page, to control the total size of the book.
// The TOC contains an entry for each page, so if each page includes a copy of the TOC,
// the total size of the page becomes O(n**2).
class MDBookSidebarScrollbox extends HTMLElement {
    constructor() {
        super();
    }
    connectedCallback() {
        this.innerHTML = '<ol class="chapter"><li class="chapter-item expanded "><a href="formats_and_languages/init.html"><strong aria-hidden="true">1.</strong> Formats &amp; Languages</a></li><li><ol class="section"><li class="chapter-item expanded "><a href="formats_and_languages/jql.html"><strong aria-hidden="true">1.1.</strong> JQL</a></li><li class="chapter-item expanded "><a href="formats_and_languages/udf.html"><strong aria-hidden="true">1.2.</strong> UDF</a></li><li class="chapter-item expanded "><a href="formats_and_languages/jel.html"><strong aria-hidden="true">1.3.</strong> JEL</a></li></ol></li><li class="chapter-item expanded "><a href="usage_guide/init.html"><strong aria-hidden="true">2.</strong> Usage Guide</a></li><li><ol class="section"><li class="chapter-item expanded "><a href="usage_guide/dropdown_menu.html"><strong aria-hidden="true">2.1.</strong> Dropdown Menu</a></li><li class="chapter-item expanded "><a href="usage_guide/selection.html"><strong aria-hidden="true">2.2.</strong> Selecting Instances</a></li><li class="chapter-item expanded "><a href="usage_guide/drag_and_drop.html"><strong aria-hidden="true">2.3.</strong> Reparenting Instances Using Drag and Drop</a></li><li class="chapter-item expanded "><a href="usage_guide/query_bar.html"><strong aria-hidden="true">2.4.</strong> Using the Search Bar</a></li><li class="chapter-item expanded "><a href="usage_guide/make_custom_icon.html"><strong aria-hidden="true">2.5.</strong> Making Custom Explorer Icons</a></li><li class="chapter-item expanded "><a href="usage_guide/tabs.html"><strong aria-hidden="true">2.6.</strong> Tabs</a></li></ol></li><li class="chapter-item expanded "><a href="editors/init.html"><strong aria-hidden="true">3.</strong> Editors</a></li><li><ol class="section"><li class="chapter-item expanded "><a href="editors/setting_editor.html"><strong aria-hidden="true">3.1.</strong> Setting Editor</a></li><li class="chapter-item expanded "><a href="editors/context_menu_editor.html"><strong aria-hidden="true">3.2.</strong> Context Menu Editor</a></li><li class="chapter-item expanded "><a href="editors/style_editor.html"><strong aria-hidden="true">3.3.</strong> Style Editor</a></li><li class="chapter-item expanded "><a href="editors/version_control_editor.html"><strong aria-hidden="true">3.4.</strong> Version Control</a></li><li class="chapter-item expanded "><a href="editors/order_editor.html"><strong aria-hidden="true">3.5.</strong> Order Editor</a></li><li class="chapter-item expanded "><a href="editors/instance_visibility_editor.html"><strong aria-hidden="true">3.6.</strong> Instance Visibility Editor</a></li></ol></li><li class="chapter-item expanded "><a href="scripting_api/init.html"><strong aria-hidden="true">4.</strong> Scripting API</a></li><li><ol class="section"><li class="chapter-item expanded "><a href="scripting_api/internal_types.html"><strong aria-hidden="true">4.1.</strong> Internal Types</a></li><li class="chapter-item expanded "><a href="scripting_api/manager_api.html"><strong aria-hidden="true">4.2.</strong> Manager API</a></li></ol></li></ol>';
        // Set the current, active page, and reveal it if it's hidden
        let current_page = document.location.href.toString().split("#")[0].split("?")[0];
        if (current_page.endsWith("/")) {
            current_page += "index.html";
        }
        var links = Array.prototype.slice.call(this.querySelectorAll("a"));
        var l = links.length;
        for (var i = 0; i < l; ++i) {
            var link = links[i];
            var href = link.getAttribute("href");
            if (href && !href.startsWith("#") && !/^(?:[a-z+]+:)?\/\//.test(href)) {
                link.href = path_to_root + href;
            }
            // The "index" page is supposed to alias the first chapter in the book.
            if (link.href === current_page || (i === 0 && path_to_root === "" && current_page.endsWith("/index.html"))) {
                link.classList.add("active");
                var parent = link.parentElement;
                if (parent && parent.classList.contains("chapter-item")) {
                    parent.classList.add("expanded");
                }
                while (parent) {
                    if (parent.tagName === "LI" && parent.previousElementSibling) {
                        if (parent.previousElementSibling.classList.contains("chapter-item")) {
                            parent.previousElementSibling.classList.add("expanded");
                        }
                    }
                    parent = parent.parentElement;
                }
            }
        }
        // Track and set sidebar scroll position
        this.addEventListener('click', function(e) {
            if (e.target.tagName === 'A') {
                sessionStorage.setItem('sidebar-scroll', this.scrollTop);
            }
        }, { passive: true });
        var sidebarScrollTop = sessionStorage.getItem('sidebar-scroll');
        sessionStorage.removeItem('sidebar-scroll');
        if (sidebarScrollTop) {
            // preserve sidebar scroll position when navigating via links within sidebar
            this.scrollTop = sidebarScrollTop;
        } else {
            // scroll sidebar to current active section when navigating via "next/previous chapter" buttons
            var activeSection = document.querySelector('#sidebar .active');
            if (activeSection) {
                activeSection.scrollIntoView({ block: 'center' });
            }
        }
        // Toggle buttons
        var sidebarAnchorToggles = document.querySelectorAll('#sidebar a.toggle');
        function toggleSection(ev) {
            ev.currentTarget.parentElement.classList.toggle('expanded');
        }
        Array.from(sidebarAnchorToggles).forEach(function (el) {
            el.addEventListener('click', toggleSection);
        });
    }
}
window.customElements.define("mdbook-sidebar-scrollbox", MDBookSidebarScrollbox);

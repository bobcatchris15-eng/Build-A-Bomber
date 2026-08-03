document.addEventListener('DOMContentLoaded', () => {
    
    // Accordion Logic
    const categoryBtns = document.querySelectorAll('.category-btn');
    
    categoryBtns.forEach(btn => {
        btn.addEventListener('click', function() {
            // Close all others
            categoryBtns.forEach(otherBtn => {
                if (otherBtn !== this) {
                    otherBtn.classList.remove('active');
                    otherBtn.nextElementSibling.classList.remove('expanded');
                }
            });
            
            // Toggle current
            this.classList.toggle('active');
            const content = this.nextElementSibling;
            content.classList.toggle('expanded');
        });
    });

    // Mock Search Filter
    const searchBar = document.querySelector('.search-bar');
    const partItems = document.querySelectorAll('.part-item');

    searchBar.addEventListener('input', (e) => {
        const term = e.target.value.toLowerCase();
        
        partItems.forEach(item => {
            const name = item.querySelector('.part-name').innerText.toLowerCase();
            const desc = item.querySelector('.part-desc').innerText.toLowerCase();
            
            if (name.includes(term) || desc.includes(term)) {
                item.style.display = 'flex';
            } else {
                item.style.display = 'none';
            }
        });
    });

    // Center Stage Click (Mocking part selection to show Grab Handles/Spec Popup)
    const centerStage = document.querySelector('.center-stage');
    const specPopup = document.getElementById('spec-popup');

    centerStage.addEventListener('click', (e) => {
        // If clicking inside the center stage, simulate selecting a part
        // and position the spec popup near the click.
        specPopup.style.display = 'block';
        specPopup.style.left = (e.clientX + 20) + 'px';
        specPopup.style.top = (e.clientY - 20) + 'px';
        specPopup.style.transform = 'none';
    });

});

// Global function for the symmetry toggle button
let symmetryEnabled = true;
function toggleSymmetry() {
    const btn = document.getElementById('sym-toggle');
    symmetryEnabled = !symmetryEnabled;
    
    if (symmetryEnabled) {
        btn.innerText = "SYMMETRY: [ON]";
        btn.style.backgroundColor = "var(--military-green)";
        btn.style.color = "#fff";
    } else {
        btn.innerText = "SYMMETRY: [OFF]";
        btn.style.backgroundColor = "var(--danger-color)";
        btn.style.color = "#fff";
    }
}

document.addEventListener('DOMContentLoaded', () => {
    
    // Radial Menu Logic
    const unitCanvas = document.getElementById('canvas-unit');
    const radialMenu = document.getElementById('radial-menu');
    const grabHandles = document.querySelectorAll('.grab-handle');

    if (unitCanvas) {
        unitCanvas.addEventListener('click', (e) => {
            // Only trigger if clicking directly on the canvas/unit, not handles
            if(e.target.classList.contains('grab-handle')) return;

            // Show Radial Menu at click position
            radialMenu.style.left = e.clientX + 'px';
            radialMenu.style.top = e.clientY + 'px';
            radialMenu.classList.add('active');

            // Show grab handles for context
            grabHandles.forEach(h => h.style.display = 'block');
        });

        // Hide radial menu if clicking elsewhere in the body
        document.body.addEventListener('click', (e) => {
            if (!unitCanvas.contains(e.target) && !radialMenu.contains(e.target)) {
                radialMenu.classList.remove('active');
                grabHandles.forEach(h => h.style.display = 'none');
            }
        });
    }
});

// Dock Tab Switching (Mock data generation)
function switchDockTab(btn, category) {
    // Reset active states
    document.querySelectorAll('.dock-tab').forEach(t => t.classList.remove('active'));
    btn.classList.add('active');

    const grid = document.querySelector('.parts-grid');
    
    // Very simple mock content swap based on category
    if (category === 'hulls') {
        grid.innerHTML = `
            <div class="part-card"><span class="part-weight">80 g</span><div class="part-name">Medium Chassis</div></div>
            <div class="part-card"><span class="part-weight">150 g</span><div class="part-name">Super-Heavy Frame</div></div>
            <div class="part-card"><span class="part-weight">45 g</span><div class="part-name">Scout Frame</div></div>
        `;
    } else if (category === 'weapons') {
        grid.innerHTML = `
            <div class="part-card"><span class="part-weight">12 g</span><div class="part-name">Ballista Core</div></div>
            <div class="part-card"><span class="part-weight">120 g</span><div class="part-name">Democracy Cannon</div></div>
            <div class="part-card"><span class="part-weight">8 g</span><div class="part-name">Gatling Array</div></div>
            <div class="part-card"><span class="part-weight">21 g</span><div class="part-name">Missile Pod</div></div>
        `;
    } else if (category === 'locomotion') {
        grid.innerHTML = `
            <div class="part-card"><span class="part-weight">30 g</span><div class="part-name">Hover Skirt</div></div>
            <div class="part-card"><span class="part-weight">50 g</span><div class="part-name">Armored Treads</div></div>
            <div class="part-card"><span class="part-weight">20 g</span><div class="part-name">Walker Legs (Quad)</div></div>
        `;
    } else {
        grid.innerHTML = `
            <div class="part-card"><span class="part-weight">5 g</span><div class="part-name">Radar Dome</div></div>
            <div class="part-card"><span class="part-weight">10 g</span><div class="part-name">Shield Generator</div></div>
        `;
    }
}

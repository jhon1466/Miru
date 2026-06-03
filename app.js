/* ==========================================================================
   Miru Landing Page Interactive Script
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
    // 1. Inicializar iconos de Lucide
    if (typeof lucide !== 'undefined') {
        lucide.createIcons();
    }

    // 1.2. Obtener el último release de GitHub de manera dinámica
    const owner = 'jhon1466';
    const repo = 'Miru';
    fetch(`https://api.github.com/repos/${owner}/${repo}/releases/latest`)
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            const apkAsset = data.assets.find(asset => asset.name.endsWith('.apk'));
            if (apkAsset) {
                const downloadUrl = apkAsset.browser_download_url;
                const releaseVersion = data.tag_name;
                const releaseSize = (apkAsset.size / (1024 * 1024)).toFixed(1);

                // Actualizar todos los botones de descarga de APK con data-github-download
                const downloadLinks = document.querySelectorAll('[data-github-download]');
                downloadLinks.forEach(link => {
                    link.href = downloadUrl;
                });

                // Actualizar todas las etiquetas que muestran la versión
                const versionTags = document.querySelectorAll('[data-github-version]');
                versionTags.forEach(tag => {
                    tag.textContent = releaseVersion;
                });

                // Actualizar todas las etiquetas que muestran el tamaño
                const sizeTags = document.querySelectorAll('[data-github-size]');
                sizeTags.forEach(tag => {
                    tag.textContent = releaseSize;
                });

                // Reiniciar los iconos por si cambiaron de contenedor
                if (typeof lucide !== 'undefined') {
                    lucide.createIcons();
                }
            }
        })
        .catch(err => {
            console.error('Error al obtener la última versión de GitHub, usando enlaces de fallback:', err);
        });

    // 2. Control de Navbar al hacer Scroll
    const navbar = document.querySelector('.navbar');
    window.addEventListener('scroll', () => {
        if (window.scrollY > 50) {
            navbar.classList.add('scrolled');
        } else {
            navbar.classList.remove('scrolled');
        }
    });

    // 3. Menú Navegación Móvil (Drawer)
    const menuToggle = document.getElementById('menuToggle');
    const drawerClose = document.getElementById('drawerClose');
    const mobileDrawer = document.getElementById('mobileDrawer');
    const drawerLinks = document.querySelectorAll('.drawer-link');

    if (menuToggle && mobileDrawer) {
        menuToggle.addEventListener('click', () => {
            mobileDrawer.classList.add('open');
        });
    }

    if (drawerClose && mobileDrawer) {
        drawerClose.addEventListener('click', () => {
            mobileDrawer.classList.remove('open');
        });
    }

    // Cerrar drawer al hacer clic en un enlace de navegación móvil
    drawerLinks.forEach(link => {
        link.addEventListener('click', () => {
            mobileDrawer.classList.remove('open');
        });
    });

    // 4. Interactividad del Acordeón FAQ
    const faqItems = document.querySelectorAll('.faq-item');

    faqItems.forEach(item => {
        const question = item.querySelector('.faq-question');
        const answer = item.querySelector('.faq-answer');

        if (question && answer) {
            question.addEventListener('click', () => {
                const isActive = item.classList.contains('active');

                // Cerrar todos los demás items activos
                faqItems.forEach(otherItem => {
                    if (otherItem !== item && otherItem.classList.contains('active')) {
                        otherItem.classList.remove('active');
                        otherItem.querySelector('.faq-answer').style.maxHeight = null;
                    }
                });

                // Toggle del item actual
                if (isActive) {
                    item.classList.remove('active');
                    answer.style.maxHeight = null;
                } else {
                    item.classList.add('active');
                    answer.style.maxHeight = answer.scrollHeight + 'px';
                }
            });
        }
    });

    // 5. Gestión del Showcase Interactivo (Tabs)
    const demoTabs = document.querySelectorAll('.demo-tab');
    const demoPanes = document.querySelectorAll('.demo-content-pane');

    demoTabs.forEach(tab => {
        tab.addEventListener('click', () => {
            const targetId = tab.getAttribute('data-target');

            // Desactivar todas las pestañas y activar la actual
            demoTabs.forEach(t => t.classList.remove('active'));
            tab.classList.add('active');

            // Ocultar todos los paneles y mostrar el seleccionado
            demoPanes.forEach(pane => {
                pane.classList.remove('active');
                if (pane.id === targetId) {
                    pane.classList.add('active');
                }
            });
        });
    });

    // 6. Animación Scroll Reveal (Intersection Observer)
    const revealElements = document.querySelectorAll('.scroll-reveal');

    if ('IntersectionObserver' in window) {
        const observerOptions = {
            root: null,
            threshold: 0.1,
            rootMargin: '0px 0px -50px 0px'
        };

        const observer = new IntersectionObserver((entries, observer) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    entry.target.classList.add('revealed');
                    observer.unobserve(entry.target); // Dejar de observar una vez animado
                }
            });
        }, observerOptions);

        revealElements.forEach(element => {
            observer.observe(element);
        });
    } else {
        // Fallback si el navegador es muy antiguo y no soporta IntersectionObserver
        revealElements.forEach(element => {
            element.classList.add('revealed');
        });
    }
});

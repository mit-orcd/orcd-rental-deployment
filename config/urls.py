# =============================================================================
# ORCD Rental Portal - Custom URL Configuration
# =============================================================================
#
# This file extends ColdFront's URL patterns to add OIDC and ORCD plugin URLs.
#
# Copy this file to /srv/coldfront/urls.py
#
# =============================================================================

from coldfront.config.urls import urlpatterns as coldfront_urlpatterns
from django.urls import path, include

# Build custom URL patterns - order matters for URL resolution
# Plugin URLs that override ColdFront core views must come FIRST
urlpatterns = [
    # ORCD Direct Charge plugin URLs (FIRST - to allow overriding core URLs)
    # These provide the rental portal, node management, billing, etc.
    # The password login view at /user/login must be matched before ColdFront's login
    path('', include('coldfront_orcd_direct_charge.urls')),

    # OIDC authentication URLs
    # These provide:
    #   /oidc/authenticate/ - Initiates OIDC login flow
    #   /oidc/callback/     - Handles callback from OIDC provider
    #   /oidc/logout/       - OIDC logout
    path('oidc/', include('mozilla_django_oidc.urls')),
]

# Add ColdFront core URLs after plugin URLs
# This allows the plugin to override specific core URL patterns
urlpatterns += coldfront_urlpatterns

# Add django-su URLs (admin user switching)
# This is used by ColdFront templates for the admin impersonation feature
try:
    import django_su
    urlpatterns += [
        path('su/', include('django_su.urls')),
    ]
except ImportError:
    pass  # django-su not installed


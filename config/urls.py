# =============================================================================
# ORCD Rental Portal - Custom URL Configuration
# =============================================================================
#
# This file extends ColdFront's URL patterns to add OIDC and ORCD plugin URLs.
#
# Copy this file to /srv/coldfront/urls.py
#
# =============================================================================

from coldfront.config.urls import urlpatterns
from django.urls import path, include

# -----------------------------------------------------------------------------
# Password Login Override
# -----------------------------------------------------------------------------
# Insert the password login URL at the BEGINNING of urlpatterns.
# This must come before ColdFront's /user/login/ to handle ?opt=password.
#
# Note: ColdFront has /user/login/ (with trailing slash), and Django's
# APPEND_SLASH would redirect /user/login to /user/login/ if no match exists.
# By inserting our /user/login (no trailing slash) first, it matches before
# the redirect can occur.
# -----------------------------------------------------------------------------
from coldfront_orcd_direct_charge.views.auth import PasswordLoginView
urlpatterns.insert(0, path('user/login', PasswordLoginView.as_view(), name='password-login'))

# Add OIDC authentication URLs
# These provide:
#   /oidc/authenticate/ - Initiates OIDC login flow
#   /oidc/callback/     - Handles callback from OIDC provider
#   /oidc/logout/       - OIDC logout
urlpatterns += [
    path('oidc/', include('mozilla_django_oidc.urls')),
]

# Add ORCD Direct Charge plugin URLs
# These provide the rental portal, node management, billing, etc.
# Note: The plugin's root URL path("") will be shadowed by ColdFront's home page,
# which is the intended behavior (ColdFront home page takes precedence).
urlpatterns += [
    path('', include('coldfront_orcd_direct_charge.urls')),
]

# Add django-su URLs (admin user switching)
# This is used by ColdFront templates for the admin impersonation feature
try:
    import django_su
    urlpatterns += [
        path('su/', include('django_su.urls')),
    ]
except ImportError:
    pass  # django-su not installed


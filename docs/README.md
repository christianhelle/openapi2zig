# openapi2zig Documentation

This directory contains the static documentation website for openapi2zig.

## Structure

- `index.html` - Main documentation page
- `styles.css` - CSS styles for the documentation
- `script.js` - JavaScript for interactive features
- `images/` - Images used in the documentation (copied from main repo)

## Development

To preview the documentation locally:

1. Open `index.html` in your web browser
2. Or use a local HTTP server:

   ```bash
   # Using Python 3
   python -m http.server 8000
   
   # Using Node.js (if you have http-server installed)
   npx http-server .
   
   # Using PHP
   php -S localhost:8000
   ```

3. Navigate to `http://localhost:8000` in your browser

## Features

- **Responsive Design**: Works on desktop, tablet, and mobile devices
- **Modern UI**: Clean, professional design with smooth animations
- **Interactive Elements**: Tabbed installation instructions, copy-to-clipboard functionality
- **Development Environment Section**: Comprehensive guide for GitHub Codespaces and dev containers
- **Dark/Light Mode**: Toggle between light and dark themes
- **Accessibility**: Keyboard navigation support and proper ARIA labels
- **Performance Optimized**: Minimal dependencies, optimized images and code

## Recent Updates

### Development Environment Integration

Added a dedicated "Development" section to the website that mirrors the new dev container configuration:

- **GitHub Codespaces Integration**: Featured prominently with direct launch link
- **One-click Development Setup**: Clear instructions for cloud-based development
- **VS Code Dev Containers**: Local development option with Docker
- **Development Workflow**: Build, test, and run commands clearly documented
- **Visual Hierarchy**: GitHub Codespaces positioned as the recommended option for contributors

## Deployment

The documentation is automatically deployed to GitHub Pages when changes are pushed to the `main` branch. The deployment is handled by the `.github/workflows/docs.yml` workflow.

### GitHub Pages Setup

To enable GitHub Pages for this repository:

1. Go to your repository settings
2. Navigate to "Pages" in the left sidebar
3. Under "Source", select "GitHub Actions"
4. The workflow will automatically deploy the documentation

## Customization

### Styling

Modify `styles.css` to change:

- Colors and themes
- Layout and spacing
- Typography
- Responsive breakpoints

### Content

Update `index.html` to:

- Add new sections
- Modify existing content
- Update links and references

### Functionality

Extend `script.js` to add:

- New interactive features
- Enhanced animations
- Additional utilities

## Browser Support

The documentation supports all modern browsers:

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

## Contributing

When contributing to the documentation:

1. Test your changes locally
2. Ensure the site is responsive across different screen sizes
3. Validate HTML markup
4. Check that all links work correctly
5. Follow the existing code style and conventions

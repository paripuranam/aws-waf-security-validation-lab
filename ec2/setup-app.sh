# Update OS
sudo yum update -y

# Install and enable Apache
sudo yum install httpd -y
sudo systemctl enable httpd && sudo systemctl start httpd

# Clone OWASP Vulnerable Web Application
cd /var/www/html
git clone https://github.com/OWASP/Vulnerable-Web-Application.git

# Move files and set index
cd Vulnerable-Web-Application
mv * /var/www/html
cd ..
mv homepage.html index.html

# Restart Apache
sudo systemctl restart httpd

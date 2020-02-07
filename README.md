# Storyteller

A template for static websites using extended markdown to create content.

This contains all the files needed to set up a static website. The host can be your own computer or a remote host.

To set up on your local computer, copy all files to an empty folder. Navigate to that folder and type `python3 rest.py`. The server will start on port 17000. Then point your browser to http://localhost:17000 and the website should come up.

To start on shared hosting, copy all the files then point your browser to `index.php` (or just use the domain name as this is the default file).

On some static hosting (e.g. Neocities) there are restrictions on the file types allowed, so remove the `.php` and `.py` files.

On your local computer or on most shared hosting, the file `scripted.html` fires up a color-coded script editor with which you can edit the supplied EasyCoder scripts. One of these is the script editor itself; the other is the viewer that runs the website.

The behavior of the site is entirely controlled by the files in the `data` folder. The file `subjects.json` determines which subjects appear as buttons on the home page. Each subject comprises a set of text files and a folder of images. The text files are:

`title.txt` The title to appear at the top of the page. If left empty the subject name will be used.

`index.txt` The markdown source of the first page of the given subject.

All other text files are markdown; their names are whatever you choose.

The system uses a customized markdown to provide additional features. You can add more by editing the script at `ecs/viewer.txt`. The ones currently provided are:

Link to a subject

Link to a topic of a subject

Add an image, with control over positioning and interactivity

Add a clear (forcing all following content to be below the current)
